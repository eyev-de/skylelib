/**
 * @file flutter_skyle_bridge.c
 * @brief FFI bridge implementation for Dart-to-C communication
 *
 * Architecture:
 * 
 * Kotlin Layer (USB Transport Only - Direct JNI Callbacks):
 * - C library's background thread calls Kotlin's read() via JNI to get USB data
 * - C library calls Kotlin's write() via JNI to send USB data
 * - Kotlin implements UsbTransportCallback interface with read() and write()
 * - Kotlin NEVER touches EAP callbacks - only handles raw USB I/O
 * - No intermediate buffering, no polling, no Kotlin threads needed
 * 
 * Dart Layer (Message Callbacks):
 * - Dart calls flutter_skyle_set_callbacks() to register message handlers
 * - Dart provides callbacks with primitive types (floats, ints, bools)
 * - C library (skyle_client) parses USB data and invokes adapter callbacks
 * - Adapters convert C structs to Dart primitives and invoke Dart callbacks
 * - Dart StreamControllers receive parsed messages
 */

#include "flutter_skyle_bridge.h"
#include "flutter_skyle_link_glue.h"
#include <skyle_client.h>
#include <skylelib/messages/skyle_message_types.h>
#include <skylelib/skyle_link.h>
#include <stdlib.h>
#include <string.h>
#include <jni.h>
#include <pthread.h>
#include <android/log.h>

#define LOG_TAG "FlutterSkyleBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// =============================================================================
// Internal structures and global state
// =============================================================================
//
// The Dart callback subscriber table (one slot per Flutter engine: main app +
// overlays), the C-to-Dart adapters, and the payload-copy rules live in the
// shared fan-out module (native/fanout/flutter_skyle_fanout.c) - this bridge
// keeps the JNI/Kotlin-transport/host-owned/context specifics and delegates
// the callback machinery.

/**
 * Bridge context - stores the Kotlin transport and client state
 */
typedef struct {
    // Kotlin USB transport callbacks (JNI)
    JavaVM* jvm;              // Java VM for getting JNI env
    jobject kotlin_callback;  // Global reference to Kotlin callback object
    jmethodID read_method;    // Method ID for read callback: fun read(buffer: ByteArray, timeout: Int): Int
    jmethodID write_method;   // Method ID for write callback: fun write(data: ByteArray): Int
    jmethodID is_device_connected_method;  // Method ID for device check: fun isDeviceConnected(): Boolean

    // Pre-allocated JNI byte arrays (global refs, reused across calls)
    jbyteArray read_buffer;       // Reusable read buffer (8192 bytes)
    jsize      read_buffer_size;  // Size of the pre-allocated read buffer
    jbyteArray write_buffer;      // Reusable write buffer (8192 bytes)
    jsize      write_buffer_size; // Size of the pre-allocated write buffer

    // Client reference
    skyle_client* client;
} bridge_context;

// Single client instance (only one client allowed at a time)
static skyle_client* g_client = NULL;
static bridge_context* g_context = NULL;

// While true the transport is owned by the Kotlin host (accessibility service):
// Dart-initiated destroy/disconnect become no-ops and connect only acts from
// DISCONNECTED, so no engine teardown can disrupt the shared link.
static bool g_host_owned = false;

void flutter_skyle_set_host_owned(bool owned) {
    g_host_owned = owned;
    LOGD("flutter_skyle_set_host_owned: transport host-owned = %d", owned ? 1 : 0);
}

static bridge_context* get_context_for_client(skyle_client* client) {
    if (!client) {
        LOGE("get_context_for_client: NULL client pointer");
        return NULL;
    }
    
    if (g_client == client) {
        return g_context;
    }
    
    // Log failure with diagnostic info (only on error, not constantly)
    LOGE("get_context_for_client: No context found for client %p", client);
    if (g_client != NULL) {
        LOGE("get_context_for_client: Registered client is %p (context=%p)", g_client, g_context);
        LOGE("get_context_for_client: Client pointer mismatch! This indicates the wrong client pointer was passed.");
    } else {
        LOGE("get_context_for_client: No client is currently registered");
    }
    return NULL;
}

static void register_client_context(skyle_client* client, bridge_context* ctx) {
    if (g_client != NULL) {
        LOGE("register_client_context: A client already exists! Only one client is allowed.");
        LOGE("register_client_context: Existing client=%p, new client=%p", g_client, client);
        LOGE("register_client_context: Destroy the existing client before creating a new one.");
        return;
    }
    
    g_client = client;
    g_context = ctx;
    LOGD("register_client_context: Registered client %p (context=%p)", client, ctx);
}

static void unregister_client_context(skyle_client* client) {
    if (g_client == client) {
        LOGD("unregister_client_context: Unregistered client %p", client);
        g_client = NULL;
        g_context = NULL;
    } else {
        LOGE("unregister_client_context: Attempted to unregister client %p, but registered client is %p", client, g_client);
    }
}

// =============================================================================
// JNI thread management - attach once, auto-detach on thread exit
// =============================================================================

// pthread_key with destructor: when a native thread exits, the destructor
// automatically calls DetachCurrentThread. This eliminates the per-call
// Attach/Detach overhead (~200+ cycles/sec) that caused GC pressure and stalls.
static pthread_key_t g_jni_thread_key;
static pthread_once_t g_jni_key_once = PTHREAD_ONCE_INIT;

static void jni_thread_destructor(void* value) {
    JavaVM* jvm = (JavaVM*)value;
    if (jvm) {
        (*jvm)->DetachCurrentThread(jvm);
        LOGD("jni_thread_destructor: Detached native thread from JVM");
    }
}

static void create_jni_thread_key(void) {
    pthread_key_create(&g_jni_thread_key, jni_thread_destructor);
}

/**
 * Get JNI environment for the current thread.
 * Attaches the thread on first call; subsequent calls return the cached env.
 * The thread is automatically detached when it exits via pthread_key destructor.
 */
static JNIEnv* get_jni_env(JavaVM* jvm) {
    if (!jvm) return NULL;

    JNIEnv* env = NULL;
    jint result = (*jvm)->GetEnv(jvm, (void**)&env, JNI_VERSION_1_6);

    if (result == JNI_OK) {
        return env;  // Already attached (main thread or previously attached native thread)
    }

    if (result == JNI_EDETACHED) {
        if ((*jvm)->AttachCurrentThread(jvm, &env, NULL) != JNI_OK) {
            LOGE("get_jni_env: AttachCurrentThread failed");
            return NULL;
        }
        // Register destructor so DetachCurrentThread is called when this thread exits
        pthread_once(&g_jni_key_once, create_jni_thread_key);
        pthread_setspecific(g_jni_thread_key, jvm);
        LOGD("get_jni_env: Attached native thread to JVM (will auto-detach on exit)");
        return env;
    }

    LOGE("get_jni_env: GetEnv failed with result=%d", result);
    return NULL;
}

// =============================================================================
// Skyle Link: Kotlin USB ownership forwarding
// =============================================================================
// (Suspension changes fan out to every engine's subscriber slot via the
// shared module: get_or_create_context registers
// flutter_skyle_fanout_dispatch_suspend_state as the link glue's process hook.)

// Kotlin USB ownership listener (SkyleUsbHost -> UsbEndpointManager). Same
// GlobalRef + mutex pattern as the Kotlin transport callback; the supervisor
// fires the trampoline on its own threads and the Kotlin side hops to a
// handler. Own JavaVM reference because the listener can be registered
// before any transport context exists.
static pthread_mutex_t g_usb_ownership_mutex = PTHREAD_MUTEX_INITIALIZER;
static JavaVM* g_usb_ownership_jvm = NULL;
static jobject g_usb_ownership_listener = NULL;
static jmethodID g_usb_ownership_on_changed = NULL;

/**
 * Trampoline registered with skyle_link_set_usb_ownership_callback: forwards
 * the supervisor's USB ownership grants/releases to the Kotlin listener.
 *
 * Ownership contract (skyle_link.h): the supervisor stops the client's
 * background threads before cb(false), and the platform must bring its
 * transport back up in cb(true). The darwin/windows bridges re-create their
 * transport there (which restarts the threads); on Android the Kotlin
 * listener only re-opens the USB device, so the bridge restarts the threads
 * itself by re-registering the (unchanged) Kotlin transport. Without this the
 * device is opened but never read - the firmware's 2.5 s heartbeat timeout
 * then soft-resets it, which re-enumerates USB in an endless detach loop.
 */
static void bridge_forward_usb_ownership(bool usb_wanted, void* user_data) {
    (void)user_data;
    pthread_mutex_lock(&g_usb_ownership_mutex);
    if (!g_usb_ownership_listener || !g_usb_ownership_jvm || !g_usb_ownership_on_changed) {
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        return;
    }

    JNIEnv* env = get_jni_env(g_usb_ownership_jvm);
    if (!env) {
        LOGE("bridge_forward_usb_ownership: Failed to get JNI environment");
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        return;
    }

    (*env)->CallVoidMethod(env, g_usb_ownership_listener, g_usb_ownership_on_changed,
                           usb_wanted ? JNI_TRUE : JNI_FALSE);
    if ((*env)->ExceptionCheck(env)) {
        LOGE("bridge_forward_usb_ownership: Exception in Kotlin listener");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
    }
    pthread_mutex_unlock(&g_usb_ownership_mutex);

    if (usb_wanted) {
        skyle_client* client = skyle_client_get_instance();
        if (client && !skyle_client_is_background_running(client)) {
            LOGD("bridge_forward_usb_ownership: restarting transport threads after ownership grant");
            if (!flutter_skyle_create_with_transport()) {
                LOGE("bridge_forward_usb_ownership: transport thread restart failed");
            }
        }
    }
}

void flutter_skyle_set_kotlin_usb_ownership_listener(void* jni_env, void* listener_obj) {
    JNIEnv* env = (JNIEnv*)jni_env;
    if (!env) {
        LOGE("flutter_skyle_set_kotlin_usb_ownership_listener: NULL env");
        return;
    }

    pthread_mutex_lock(&g_usb_ownership_mutex);

    if (g_usb_ownership_listener) {
        (*env)->DeleteGlobalRef(env, g_usb_ownership_listener);
        g_usb_ownership_listener = NULL;
        g_usb_ownership_on_changed = NULL;
    }

    if (!listener_obj) {
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        // Clear the supervisor slot outside our mutex: an in-flight trampoline
        // holds it while dispatching and bails on the NULLed listener.
        skyle_link_set_usb_ownership_callback(NULL, NULL);
        LOGD("flutter_skyle_set_kotlin_usb_ownership_listener: listener cleared");
        return;
    }

    if ((*env)->GetJavaVM(env, &g_usb_ownership_jvm) != JNI_OK) {
        LOGE("flutter_skyle_set_kotlin_usb_ownership_listener: Failed to get JavaVM");
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        return;
    }

    jobject listener = (jobject)listener_obj;
    g_usb_ownership_listener = (*env)->NewGlobalRef(env, listener);
    if (!g_usb_ownership_listener) {
        LOGE("flutter_skyle_set_kotlin_usb_ownership_listener: Failed to create global reference");
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        return;
    }

    jclass listenerClass = (*env)->GetObjectClass(env, g_usb_ownership_listener);
    // fun onUsbOwnershipChanged(wanted: Boolean)
    g_usb_ownership_on_changed = (*env)->GetMethodID(env, listenerClass, "onUsbOwnershipChanged", "(Z)V");
    (*env)->DeleteLocalRef(env, listenerClass);
    if (!g_usb_ownership_on_changed) {
        LOGE("flutter_skyle_set_kotlin_usb_ownership_listener: Failed to find onUsbOwnershipChanged method");
        (*env)->DeleteGlobalRef(env, g_usb_ownership_listener);
        g_usb_ownership_listener = NULL;
        pthread_mutex_unlock(&g_usb_ownership_mutex);
        return;
    }

    pthread_mutex_unlock(&g_usb_ownership_mutex);

    // Register (or re-register) the trampoline with the supervisor AFTER the
    // listener is in place so no grant is dispatched into a half-set slot.
    skyle_link_set_usb_ownership_callback(bridge_forward_usb_ownership, NULL);
    LOGD("flutter_skyle_set_kotlin_usb_ownership_listener: USB ownership listener registered");
}

// =============================================================================
// Transport layer callbacks (USB I/O stubs for Android)
// =============================================================================

/**
 * USB device presence check - calls Kotlin to verify device is still connected
 */
static bool usb_device_check(void* user_data) {
    bridge_context* ctx = (bridge_context*)user_data;

    if (!ctx || !ctx->jvm || !ctx->kotlin_callback || !ctx->is_device_connected_method) {
        return false;
    }

    JNIEnv* env = get_jni_env(ctx->jvm);
    if (!env) {
        LOGE("usb_device_check: Failed to get JNI environment");
        return false;
    }

    jboolean isConnected = (*env)->CallBooleanMethod(env, ctx->kotlin_callback, ctx->is_device_connected_method);

    if ((*env)->ExceptionCheck(env)) {
        LOGE("usb_device_check: Exception in Kotlin callback");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        isConnected = false;
    }

    return (bool)isConnected;
}

/**
 * Transport write function - calls Kotlin directly via JNI to send USB data
 * This is called by the C library when it needs to send data to the device.
 *
 * Write arrays are allocated per-call because Kotlin's write() uses data.size
 * to determine how many bytes to send via bulkTransfer, so the array must be
 * exactly the right size. The main optimization here is get_jni_env() which
 * eliminates the per-call AttachCurrentThread/DetachCurrentThread overhead.
 */
static int transport_write(const uint8_t* data, uint16_t length, void* user_data) {
    bridge_context* ctx = (bridge_context*)user_data;

    if (!ctx || !data || length == 0) {
        return -1;
    }

    if (!ctx->jvm || !ctx->kotlin_callback || !ctx->write_method) {
        LOGE("transport_write: Kotlin callback not set - cannot write");
        return -1;
    }

    JNIEnv* env = get_jni_env(ctx->jvm);
    if (!env) {
        LOGE("transport_write: Failed to get JNI environment");
        return -1;
    }

    jbyteArray jdata = (*env)->NewByteArray(env, (jsize)length);
    if (!jdata) {
        LOGE("transport_write: Failed to create byte array");
        return -1;
    }

    (*env)->SetByteArrayRegion(env, jdata, 0, (jsize)length, (const jbyte*)data);

    jint bytesWritten = (*env)->CallIntMethod(env, ctx->kotlin_callback, ctx->write_method, jdata);

    if ((*env)->ExceptionCheck(env)) {
        LOGE("transport_write: Exception in Kotlin callback");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        bytesWritten = -1;
    }

    (*env)->DeleteLocalRef(env, jdata);

    return (int)bytesWritten;
}

/**
 * Transport read function - calls Kotlin directly via JNI to read USB data
 * This is called by the C library's background thread when it needs data.
 *
 * Uses a pre-allocated read buffer (global ref) to eliminate the 8KB allocation
 * that previously occurred on every poll cycle (~200/sec = 1.6 MB/sec of garbage).
 * The read buffer size is always 8192 (sizeof(skyle_client.read_buffer)), so the
 * pre-allocated array is reused on every call.
 */
static int transport_read(uint8_t* buffer, uint16_t buffer_size, uint32_t timeout_ms, void* user_data) {
    bridge_context* ctx = (bridge_context*)user_data;

    if (!ctx || !buffer || buffer_size == 0) {
        return -1;
    }

    if (!ctx->jvm || !ctx->kotlin_callback || !ctx->read_method) {
        LOGE("transport_read: Kotlin callback not set - cannot read");
        return -1;
    }

    JNIEnv* env = get_jni_env(ctx->jvm);
    if (!env) {
        LOGE("transport_read: Failed to get JNI environment");
        return -1;
    }

    // Use pre-allocated buffer if size matches, otherwise create a temporary one
    jbyteArray jbuffer;
    bool using_temp_buffer = false;

    if (ctx->read_buffer && buffer_size <= ctx->read_buffer_size) {
        jbuffer = ctx->read_buffer;
    } else {
        jbuffer = (*env)->NewByteArray(env, (jsize)buffer_size);
        if (!jbuffer) {
            LOGE("transport_read: Failed to create byte array");
            return -1;
        }
        using_temp_buffer = true;
    }

    jint bytesRead = (*env)->CallIntMethod(env, ctx->kotlin_callback, ctx->read_method,
                                           jbuffer, (jint)timeout_ms);

    if ((*env)->ExceptionCheck(env)) {
        LOGE("transport_read: Exception in Kotlin callback");
        (*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        bytesRead = -1;
    }

    if (bytesRead > 0) {
        (*env)->GetByteArrayRegion(env, jbuffer, 0, bytesRead, (jbyte*)buffer);
    }

    if (using_temp_buffer) {
        (*env)->DeleteLocalRef(env, jbuffer);
    }

    return (int)bytesRead;
}


// =============================================================================
// Public API Implementation
// =============================================================================

/**
 * Get the bridge context for the client, creating and registering it if this
 * is the first touch (transport config from Kotlin or callback registration
 * from Dart can each come first).
 */
static bridge_context* get_or_create_context(skyle_client* client) {
    bridge_context* ctx = get_context_for_client(client);
    if (ctx != NULL) {
        return ctx;
    }

    ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
    if (!ctx) {
        LOGE("get_or_create_context: Failed to allocate context");
        return NULL;
    }

    ctx->client = client;

    register_client_context(client, ctx);

    // Wire the Skyle Link glue's process hook (idempotent re-assignment):
    // suspension changes fan out to every engine's subscriber slot via the
    // shared fan-out module. Then install the glue's event adapters
    // (supervisor hub events + client-level suspension callback) once - this
    // runs with zero Dart engines when SkyleUsbHost starts the transport.
    flutter_skyle_link_glue_set_fanout_hook(flutter_skyle_fanout_dispatch_suspend_state);
    flutter_skyle_link_glue_install(client);

    LOGD("get_or_create_context: Created new context for client %p", client);
    return ctx;
}

skyle_client* flutter_skyle_create_with_transport(void) {
    // Get or create singleton client instance
    skyle_client* client = skyle_client_get_instance();
    if (!client) {
        LOGE("flutter_skyle_create_with_transport: Failed to get client instance");
        return NULL;
    }

    bridge_context* ctx = get_or_create_context(client);
    if (!ctx) {
        return NULL;
    }

    // Set transport configuration (bridge provides transport functions)
    skyle_transport_config transport_config = {
        .transport_write = transport_write,
        .transport_read = transport_read,
        .usb_device_check = usb_device_check,
        .transport_user_data = ctx,
        .connect_timeout_ms = 10000,  // Increase timeout to 10 seconds
        .reconnect_interval_ms = 1000,
        .verbose = false,   // Verbose logging: see upload thread + send thread progress
        .trace = false     // Per-packet trace logging (very spammy)
    };

    skyle_result result = skyle_client_set_transport(client, &transport_config);
    if (result != SKYLE_OK) {
        LOGE("flutter_skyle_create_with_transport: skyle_client_set_transport failed (%d)", result);
        return NULL;
    }

    // Check if background thread is running
    bool bg_running = skyle_client_is_background_running(client);
    LOGD("flutter_skyle_create_with_transport: Transport configured successfully (client=%p, ctx=%p, bg_thread_running=%d)", client, ctx, bg_running);
    return client;
}

void flutter_skyle_set_kotlin_transport(skyle_client* client, void* jni_env, void* kotlin_callback_obj) {
    if (!client || !jni_env || !kotlin_callback_obj) {
        LOGE("flutter_skyle_set_kotlin_transport: Invalid parameters");
        return;
    }

    JNIEnv* env = (JNIEnv*)jni_env;
    jobject callback = (jobject)kotlin_callback_obj;

    // Create the context on demand: the service-owned host (SkyleUsbHost)
    // registers the transport BEFORE any Dart engine has subscribed callbacks.
    // The old get_context_for_client here silently no-oped in that order,
    // leaving the C threads without a USB callback - device check permanently
    // false, handshake never started.
    bridge_context* ctx = get_or_create_context(client);
    if (!ctx) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to get/create context");
        return;
    }

    // Get JavaVM from JNIEnv
    if ((*env)->GetJavaVM(env, &ctx->jvm) != JNI_OK) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to get JavaVM");
        return;
    }

    // Release any previous registration first: without this, re-registration
    // leaked the global refs AND kept the old UsbEndpointManager (with its open
    // UsbDeviceConnection) alive forever, still being read through.
    if (ctx->kotlin_callback) {
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        ctx->kotlin_callback = NULL;
    }
    if (ctx->read_buffer) {
        (*env)->DeleteGlobalRef(env, ctx->read_buffer);
        ctx->read_buffer = NULL;
        ctx->read_buffer_size = 0;
    }

    // Create global reference to callback object (so it survives across JNI calls)
    ctx->kotlin_callback = (*env)->NewGlobalRef(env, callback);
    if (!ctx->kotlin_callback) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to create global reference");
        return;
    }

    // Get method IDs
    jclass callbackClass = (*env)->GetObjectClass(env, ctx->kotlin_callback);
    
    // fun read(buffer: ByteArray, timeout: Int): Int
    ctx->read_method = (*env)->GetMethodID(env, callbackClass, "read", "([BI)I");
    if (!ctx->read_method) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to find read method");
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        (*env)->DeleteLocalRef(env, callbackClass);
        ctx->kotlin_callback = NULL;
        return;
    }
    
    // fun write(data: ByteArray): Int
    ctx->write_method = (*env)->GetMethodID(env, callbackClass, "write", "([B)I");
    if (!ctx->write_method) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to find write method");
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        (*env)->DeleteLocalRef(env, callbackClass);
        ctx->kotlin_callback = NULL;
        return;
    }

    // fun isDeviceConnected(): Boolean
    ctx->is_device_connected_method = (*env)->GetMethodID(env, callbackClass, "isDeviceConnected", "()Z");
    if (!ctx->is_device_connected_method) {
        LOGE("flutter_skyle_set_kotlin_transport: Failed to find isDeviceConnected method");
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        (*env)->DeleteLocalRef(env, callbackClass);
        ctx->kotlin_callback = NULL;
        return;
    }

    (*env)->DeleteLocalRef(env, callbackClass);

    // Pre-allocate reusable read buffer as a global ref.
    // The C background thread calls transport_read() ~200 times/sec with buffer_size=8192.
    // Without this, each call allocated a new 8KB Java array (1.6 MB/sec of garbage).
    {
        const jsize READ_BUFFER_SIZE = 8192;
        jbyteArray localBuf = (*env)->NewByteArray(env, READ_BUFFER_SIZE);
        if (localBuf) {
            ctx->read_buffer = (*env)->NewGlobalRef(env, localBuf);
            ctx->read_buffer_size = READ_BUFFER_SIZE;
            (*env)->DeleteLocalRef(env, localBuf);
            LOGD("flutter_skyle_set_kotlin_transport: Pre-allocated %d-byte read buffer", READ_BUFFER_SIZE);
        } else {
            LOGE("flutter_skyle_set_kotlin_transport: Failed to pre-allocate read buffer (will fall back to per-call allocation)");
            ctx->read_buffer = NULL;
            ctx->read_buffer_size = 0;
        }
    }

    LOGD("flutter_skyle_set_kotlin_transport: Kotlin transport callbacks registered successfully (read + write + isDeviceConnected)");
}

bool flutter_skyle_is_initialized(void) {
    return g_context != NULL;
}

skyle_client* flutter_skyle_get_instance(void) {
    return skyle_client_get_instance();
}

int64_t flutter_skyle_add_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks) {
    return flutter_skyle_add_callbacks_engine(client, callbacks, 0);
}

int64_t flutter_skyle_add_callbacks_engine(skyle_client* client, const flutter_skyle_callbacks* callbacks, int64_t engine_token) {
    if (!client || !callbacks) {
        LOGE("flutter_skyle_add_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = get_or_create_context(client);
    if (!ctx) {
        return -1;
    }

    // Table + adapter installation live in the shared fan-out module. On
    // Android Dart passes no engine token (0) - stale-subscriber reaping is
    // the Kotlin plugin's job (reportSubscriberHandle -> onDetachedFromEngine).
    int64_t handle = flutter_skyle_fanout_add(client, callbacks, engine_token);
    if (handle == -2) {
        LOGE("flutter_skyle_add_callbacks: Subscriber table full (%d slots)", FLUTTER_SKYLE_MAX_SUBSCRIBERS);
        return -2;
    }
    if (handle <= 0) {
        return -1;
    }

    LOGD("flutter_skyle_add_callbacks: Registered subscriber handle=%lld for client %p", (long long)handle, client);
    return handle;
}

int flutter_skyle_remove_callbacks(skyle_client* client, int64_t handle) {
    if (!client || handle <= 0) {
        return -1;
    }

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        return -1;
    }

    // The module deliberately does NOT unregister the core adapters even when
    // the table is now empty: other engines may subscribe at any time, and
    // empty-table adapters are cheap no-ops.
    int result = flutter_skyle_fanout_remove(handle);
    LOGD("flutter_skyle_remove_callbacks: handle=%lld -> %s", (long long)handle,
         result == 0 ? "removed" : "not found");
    return result;
}

int flutter_skyle_set_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks) {
    if (!client || !callbacks) {
        LOGE("flutter_skyle_set_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = get_or_create_context(client);
    if (!ctx) {
        return -1;
    }

    // Legacy replace-all-with-one semantics (module: clear the whole
    // subscriber table, register the caller as the only subscriber).
    int result = flutter_skyle_fanout_set_single(client, callbacks);
    if (result != 0) {
        return result;
    }

    LOGD("flutter_skyle_set_callbacks: Callbacks registered successfully for client %p (legacy single-subscriber mode)", client);
    return 0;
}

void flutter_skyle_clear_callbacks(skyle_client* client) {
    if (!client) {
        return;
    }

    LOGD("flutter_skyle_clear_callbacks: Clearing callbacks for client %p", client);

    // Get context from map
    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGD("flutter_skyle_clear_callbacks: No context found, nothing to clear");
        return;
    }

    // Module: zero ALL subscriber slots under the mutex (atomic for any
    // adapter currently dispatching), then unregister the C adapters from
    // skyle_client so eap_process_message does not even reach them.
    // Belt-and-suspenders against the case where a Dart NativeCallable has
    // been closed without our destroy() running - e.g. engine teardown racing
    // with an in-flight read on the I/O thread. A later
    // flutter_skyle_set_callbacks/add_callbacks call re-registers the adapters.
    flutter_skyle_fanout_clear(client);

    LOGD("flutter_skyle_clear_callbacks: Callbacks cleared successfully");
}

void flutter_skyle_destroy(skyle_client* client) {
    if (!client) {
        return;
    }

    if (g_host_owned) {
        LOGD("flutter_skyle_destroy: suppressed - transport is host-owned (accessibility service)");
        return;
    }

    LOGD("flutter_skyle_destroy: Starting destruction for client %p", client);

    // Clear Dart callbacks first to prevent any stray invocations
    flutter_skyle_clear_callbacks(client);

    // Get context from map
    bridge_context* ctx = get_context_for_client(client);

    // Also clear the C-level adapter callbacks before destroying
    // (safe since we're about to stop all threads anyway)
    skyle_callback_config empty_config = {0};
    skyle_client_set_callbacks(client, &empty_config);

    // Destroy client (this stops background thread and waits for it)
    skyle_client_destroy(client);

    // Clean up JNI global references
    if (ctx) {
        JNIEnv* env = NULL;
        if (ctx->jvm) {
            env = get_jni_env(ctx->jvm);
        }

        if (env) {
            if (ctx->read_buffer) {
                (*env)->DeleteGlobalRef(env, ctx->read_buffer);
                ctx->read_buffer = NULL;
            }
            if (ctx->kotlin_callback) {
                (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
                ctx->kotlin_callback = NULL;
            }
        }
    }

    // Unregister from map
    unregister_client_context(client);

    // Free context
    if (ctx) {
        free(ctx);
    }

    LOGD("flutter_skyle_destroy: Client destroyed");
}

int flutter_skyle_connect(skyle_client* client) {
    if (!client) {
        return -1;
    }

    // Check current state
    skyle_connection_state current_state = skyle_client_get_state(client);
    LOGD("flutter_skyle_connect: Current state: %d", (int)current_state);

    // While the transport is host-owned, a Dart-initiated connect must never
    // force-reset an already established link (per-engine retry loops would
    // otherwise disrupt the shared connection).
    if (g_host_owned && current_state != SKYLE_STATE_DISCONNECTED) {
        LOGD("flutter_skyle_connect: no-op - host-owned transport already active (state=%d)", (int)current_state);
        return 0;
    }

    // If not disconnected, reset state first - but never while the transport
    // supervisor runs (it would kill a healthy local link or a supervisor-
    // managed USB session; skyle_client_connect is a supervisor kick then).
    if (current_state != SKYLE_STATE_DISCONNECTED && !skyle_link_supervisor_is_enabled()) {
        LOGD("flutter_skyle_connect: Client not in DISCONNECTED state (%d), resetting...", (int)current_state);
        skyle_client_disconnect(client);
        current_state = skyle_client_get_state(client);
        LOGD("flutter_skyle_connect: State after reset: %d", (int)current_state);
    }

    // skyle_client_connect will start background thread if needed
    // Connect to device (background thread will handle handshake automatically)
    skyle_result result = skyle_client_connect(client);
    if (result != SKYLE_OK) {
        LOGE("flutter_skyle_connect: Connect failed (%d)", result);
        return result;
    }

    LOGD("flutter_skyle_connect: Connected - background thread handles all I/O automatically");
    return 0;
}

int flutter_skyle_disconnect(skyle_client* client) {
    if (!client) {
        return -1;
    }

    if (g_host_owned) {
        LOGD("flutter_skyle_disconnect: suppressed - transport is host-owned (accessibility service)");
        return 0;
    }

    // Stop background thread first
    skyle_result bg_result = skyle_client_stop_background(client);
    if (bg_result != SKYLE_OK) {
        LOGD("flutter_skyle_disconnect: Background thread stop result: %d (may already be stopped)", bg_result);
    }

    // Disconnect client
    skyle_result result = skyle_client_disconnect(client);

    LOGD("flutter_skyle_disconnect: Disconnected");
    return result;
}

int flutter_skyle_enable_gaze(skyle_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_enable_gaze(client, enable);
    LOGD("flutter_skyle_enable_gaze: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_skyle_enable_positioning(skyle_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_enable_positioning(client, enable);
    LOGD("flutter_skyle_enable_positioning: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_skyle_request_version(skyle_client* client) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_request_version(client);
    LOGD("flutter_skyle_request_version: Requested (%d)", result);
    return result;
}

int flutter_skyle_enable_control(skyle_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_enable_control(client, enable);
    LOGD("flutter_skyle_enable_control: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_skyle_send_control(skyle_client* client, const skyle_control_message* message) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_send_control(client, message);
    LOGD("flutter_skyle_send_control: (%d)", result);
    return result;
}

int flutter_skyle_send_display_info(skyle_client* client, const skyle_set_display_info* info) {
    if (!client || !info) {
        return -1;
    }

    skyle_result result = skyle_client_send_display_info(client, info);
    LOGD("flutter_skyle_send_display_info: %ux%upx %.1fx%.1fmm (%d)",
         info->resolution.width, info->resolution.height,
         info->size_mm.width, info->size_mm.height, result);
    return result;
}

int flutter_skyle_start_calibration(skyle_client* client, const skyle_calibration_config* config) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_start_calibration(client, config);
    LOGD("flutter_skyle_start_calibration: (%d)", result);
    return result;
}

int flutter_skyle_collect_calibration_points(skyle_client* client) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_collect_calibration_points(client);
    LOGD("flutter_skyle_collect_calibration_points: (%d)", result);
    return result;
}

int flutter_skyle_abort_calibration(skyle_client* client) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_abort_calibration(client);
    LOGD("flutter_skyle_abort_calibration: (%d)", result);
    return result;
}

int flutter_skyle_enable_video(skyle_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_enable_video(client, enable);
    LOGD("flutter_skyle_enable_video: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_skyle_enable_logging(skyle_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    skyle_result result = skyle_client_enable_logging(client, enable);
    LOGD("flutter_skyle_enable_logging: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

// flutter_skyle_feed_usb_data() is NO LONGER NEEDED
// The C library now calls transport_read() which directly calls Kotlin's read() via JNI
// No intermediate buffering required

int flutter_skyle_get_state(skyle_client* client) {
    if (!client) {
        return -1;
    }

    return (int)skyle_client_get_state(client);
}

const char* flutter_skyle_get_last_error(skyle_client* client) {
    if (!client) {
        return NULL;
    }

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        return NULL;
    }

    // The error buffer lives in the fan-out module (its on_error adapter
    // records the message before dispatching to the subscribers).
    return flutter_skyle_fanout_last_error();
}

// =============================================================================
// Helper function to retrieve pending write data for Kotlin
// =============================================================================

// REMOVED: getPendingWrite and clearPendingWrite
// Now using direct JNI callbacks - C calls Kotlin's write() method directly

// =============================================================================
// File Transfer Functions
// =============================================================================

int flutter_skyle_upload_file(skyle_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash) {
    if (!client || !path || !data) return -1;
    skyle_result result = skyle_client_upload_file(client, path, data, data_len, sha256_hash);
    LOGD("flutter_skyle_upload_file: path=%s, size=%u (%d)", path, data_len, result);
    return result;
}

int flutter_skyle_cancel_upload(skyle_client* client) {
    if (!client) return -1;
    skyle_result result = skyle_client_cancel_upload(client);
    LOGD("flutter_skyle_cancel_upload: (%d)", result);
    return result;
}

void flutter_skyle_free(void* ptr) {
    free(ptr);
}
