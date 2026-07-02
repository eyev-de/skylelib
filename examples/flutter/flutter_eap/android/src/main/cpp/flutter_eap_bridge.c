/**
 * @file flutter_eap_bridge.c
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
 * - Dart calls flutter_eap_set_callbacks() to register message handlers
 * - Dart provides callbacks with primitive types (floats, ints, bools)
 * - C library (eap_client) parses USB data and invokes adapter callbacks
 * - Adapters convert C structs to Dart primitives and invoke Dart callbacks
 * - Dart StreamControllers receive parsed messages
 */

#include "flutter_eap_bridge.h"
#include <eap_client.h>
#include <skylelib/eap/eap_message_types.h>
#include <stdlib.h>
#include <string.h>
#include <jni.h>
#include <pthread.h>
#include <android/log.h>

#define LOG_TAG "FlutterEapBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// =============================================================================
// Internal structures and global state
// =============================================================================

/**
 * Bridge context - stores Dart callbacks, Kotlin transport, and client state
 */
typedef struct {
    flutter_eap_callbacks dart_callbacks;
    pthread_mutex_t callback_mutex;  // Protects dart_callbacks against dispatch thread race

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

    // Error handling
    char last_error[256];

    // Deep copies of calibration result arrays kept alive for async Dart callback
    eap_quality_point* calib_left_copy;
    eap_quality_point* calib_right_copy;

    // Client reference
    eap_client* client;
} bridge_context;

// Single client instance (only one client allowed at a time)
static eap_client* g_client = NULL;
static bridge_context* g_context = NULL;

static bridge_context* get_context_for_client(eap_client* client) {
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

static void register_client_context(eap_client* client, bridge_context* ctx) {
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

static void unregister_client_context(eap_client* client) {
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
 * The read buffer size is always 8192 (sizeof(eap_client.read_buffer)), so the
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
// C-to-Dart callback adapters
// =============================================================================
//
// NOTE: These adapters are ONLY used by Dart, NOT by Kotlin!
//
// Architecture:
// - Kotlin layer: ONLY uses transport functions via JNI
//   → Kotlin never touches callbacks at all
// - Dart layer: Sets callbacks via flutter_eap_set_callbacks()
//   → Dart receives complete C structs via FFI
// - C library: Invokes callbacks with C structs
// - These adapters: Pass C struct pointers directly to Dart
//   → Only registered when Dart calls flutter_eap_set_callbacks()
//   → Called by C library background thread when messages are parsed
//
// Why minimal: Dart FFI can access C structs directly - no conversion needed
//

/**
 * Gaze callback adapter - passes eap_gaze_response struct directly to Dart
 */
static void on_gaze_adapter(eap_client* client, const eap_gaze_response* data, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    // Mutex protects against hot restart clearing dart_callbacks between check and call
    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_gaze) {
        ctx->dart_callbacks.on_gaze(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Positioning callback adapter - passes eap_positioning_response struct directly to Dart
 */
static void on_positioning_adapter(eap_client* client, const eap_positioning_response* data, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_positioning) {
        ctx->dart_callbacks.on_positioning(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Version callback adapter - passes eap_version_response struct directly to Dart
 */
static void on_version_adapter(eap_client* client, const eap_version_response* version, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !version) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_version) {
        ctx->dart_callbacks.on_version(*version, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Control callback adapter - passes eap_control_message struct directly to Dart
 */
static void on_control_adapter(eap_client* client, const eap_control_message* data, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_control) {
        ctx->dart_callbacks.on_control(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Calibration point callback adapter - passes eap_next_calibration_point struct directly to Dart
 */
static void on_calibration_point_adapter(eap_client* client, const eap_next_calibration_point* point, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !point) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_point) {
        ctx->dart_callbacks.on_calibration_point(*point, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Calibration progress callback adapter - passes eap_collecting_calibration_points struct directly to Dart
 */
static void on_calibration_progress_adapter(eap_client* client, const eap_collecting_calibration_points* progress, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !progress) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_progress) {
        ctx->dart_callbacks.on_calibration_progress(*progress, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Calibration paused callback adapter
 */
static void on_calibration_paused_adapter(eap_client* client, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_paused) {
        ctx->dart_callbacks.on_calibration_paused(ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Calibration finished callback adapter - passes eap_finished_calibration struct directly to Dart
 */
static void on_calibration_finished_adapter(eap_client* client, const eap_finished_calibration* result, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !result) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_finished) {
        // Deep copy quality point arrays - NativeCallable.listener is async,
        // so the original arrays will be freed before Dart processes the callback.
        free(ctx->calib_left_copy);
        free(ctx->calib_right_copy);
        ctx->calib_left_copy = NULL;
        ctx->calib_right_copy = NULL;

        eap_finished_calibration copy = *result;

        if (result->left_count > 0 && result->left) {
            size_t left_size = result->left_count * sizeof(eap_quality_point);
            ctx->calib_left_copy = (eap_quality_point*)malloc(left_size);
            if (ctx->calib_left_copy) {
                memcpy(ctx->calib_left_copy, result->left, left_size);
                copy.left = ctx->calib_left_copy;
            }
        }

        if (result->right_count > 0 && result->right) {
            size_t right_size = result->right_count * sizeof(eap_quality_point);
            ctx->calib_right_copy = (eap_quality_point*)malloc(right_size);
            if (ctx->calib_right_copy) {
                memcpy(ctx->calib_right_copy, result->right, right_size);
                copy.right = ctx->calib_right_copy;
            }
        }

        ctx->dart_callbacks.on_calibration_finished(copy, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * State change callback adapter
 */
static void on_state_change_adapter(eap_client* client, eap_connection_state old_state,
                                    eap_connection_state new_state, void* user_data) {
    (void)client;      // Unused
    (void)old_state;   // Unused - Dart only needs new state
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_state_change) {
        ctx->dart_callbacks.on_state_change((int)new_state, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Error callback adapter
 */
static void on_error_adapter(eap_client* client, eap_result error, const char* message, void* user_data) {
    (void)client;  // Unused
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !message) return;

    // Log error for debugging
    LOGE("on_error_adapter: Error code=%d, message='%s'", (int)error, message);

    // Store error message
    strncpy(ctx->last_error, message, sizeof(ctx->last_error) - 1);
    ctx->last_error[sizeof(ctx->last_error) - 1] = '\0';

    // Invoke Dart callback
    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_error) {
        ctx->dart_callbacks.on_error(message, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Video frame callback adapter
 * Called directly from I/O thread when a chunked transfer completes.
 * Data pointer is only valid during this callback.
 * Converts to RGBA in C (compiler auto-vectorises) so Dart receives
 * ready-to-display pixels with no per-pixel loop on the UI thread.
 */
static void on_video_adapter(eap_client* client, const eap_video_response* video,
                              void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !video || !video->pixel_data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_video) {
        const uint32_t pixel_count = (uint32_t)video->width * (uint32_t)video->height;
        const uint64_t rgba_size_64 = (uint64_t)pixel_count * 4;
        if (pixel_count == 0 || rgba_size_64 > (64u * 1024u * 1024u)) {
            pthread_mutex_unlock(&ctx->callback_mutex);
            return;
        }
        const uint32_t rgba_size = (uint32_t)rgba_size_64;
        uint8_t* rgba = (uint8_t*)malloc(rgba_size);
        if (rgba) {
            const uint8_t* src = video->pixel_data;
            switch (video->channels) {
                case 1: // Grayscale -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        const uint8_t v = src[i];
                        rgba[i * 4]     = v;
                        rgba[i * 4 + 1] = v;
                        rgba[i * 4 + 2] = v;
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
                case 3: // BGR -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        rgba[i * 4]     = src[i * 3 + 2];
                        rgba[i * 4 + 1] = src[i * 3 + 1];
                        rgba[i * 4 + 2] = src[i * 3];
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
                case 4: // BGRA -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        rgba[i * 4]     = src[i * 4 + 2];
                        rgba[i * 4 + 1] = src[i * 4 + 1];
                        rgba[i * 4 + 2] = src[i * 4];
                        rgba[i * 4 + 3] = src[i * 4 + 3];
                    }
                    break;
                default: // Fallback: treat as grayscale
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        const uint8_t v = src[i % video->pixel_data_length];
                        rgba[i * 4]     = v;
                        rgba[i * 4 + 1] = v;
                        rgba[i * 4 + 2] = v;
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
            }
            ctx->dart_callbacks.on_video(rgba, rgba_size,
                                         video->width, video->height, 4,
                                         ctx->dart_callbacks.user_data);
        }
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * File status callback adapter
 * Called when device sends StatusFile response during file transfer.
 */
static void on_file_status_adapter(eap_client* client,
    const eap_file_status_response* status, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !status) {
        LOGE("on_file_status_adapter: NULL ctx=%p or status=%p", (void*)ctx, (const void*)status);
        return;
    }

    LOGD("on_file_status_adapter: status=%d progress=%d error='%s'",
         (int)status->status, (int)status->progress,
         (status->error_message[0] != '\0') ? status->error_message : "(none)");

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_file_status) {
        // NativeCallable.listener posts to a Dart port — the callback runs
        // asynchronously. Heap-allocate the error string so it survives.
        // Dart frees it after reading.
        char* error_msg = NULL;
        if (status->status == EAP_FILE_STATUS_FAILED && status->error_message[0] != '\0') {
            error_msg = strdup(status->error_message);
        }
        ctx->dart_callbacks.on_file_status(
            (uint16_t)status->status,
            status->progress,
            error_msg,
            ctx->dart_callbacks.user_data
        );
        LOGD("on_file_status_adapter: Dart callback invoked");
    } else {
        LOGE("on_file_status_adapter: dart_callbacks.on_file_status is NULL — Dart will not receive this event!");
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

/**
 * Logging callback adapter — forwards device log lines to Dart.
 * The message is heap-allocated (strdup) so it survives the async hop to
 * Dart via NativeCallable.listener; Dart frees it with flutter_eap_free.
 */
static void on_logging_adapter(eap_client* client,
    const eap_logging_response* log, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !log) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_logging) {
        char* msg = (log->message_len > 0) ? strdup(log->message) : NULL;
        ctx->dart_callbacks.on_logging(
            (uint8_t)log->level,
            msg,
            log->header.timestamp_ms,
            ctx->dart_callbacks.user_data
        );
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

// =============================================================================
// Public API Implementation
// =============================================================================

eap_client* flutter_eap_create_with_transport(void) {
    // Get or create singleton client instance
    eap_client* client = eap_client_get_instance();
    if (!client) {
        LOGE("flutter_eap_create_with_transport: Failed to get client instance");
        return NULL;
    }

    // Check if we already have a context for this client
    bridge_context* ctx = get_context_for_client(client);
    
    // Create context if it doesn't exist
    if (ctx == NULL) {
        // Allocate bridge context
        ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
        if (!ctx) {
            LOGE("flutter_eap_create_with_transport: Failed to allocate context");
            return NULL;
        }

        // Initialize callback mutex (protects dart_callbacks during hot restart swap)
        pthread_mutex_init(&ctx->callback_mutex, NULL);

        // Initialize state
        ctx->jvm = NULL;
        ctx->kotlin_callback = NULL;
        ctx->read_method = NULL;
        ctx->write_method = NULL;
        ctx->is_device_connected_method = NULL;
        ctx->read_buffer = NULL;
        ctx->read_buffer_size = 0;
        ctx->write_buffer = NULL;
        ctx->write_buffer_size = 0;
        ctx->client = client;

        register_client_context(client, ctx);
    }

    // Set transport configuration (bridge provides transport functions)
    eap_transport_config transport_config = {
        .transport_write = transport_write,
        .transport_read = transport_read,
        .usb_device_check = usb_device_check,
        .transport_user_data = ctx,
        .connect_timeout_ms = 10000,  // Increase timeout to 10 seconds
        .reconnect_interval_ms = 1000,
        .verbose = false,   // Verbose logging: see upload thread + send thread progress
        .trace = false     // Per-packet trace logging (very spammy)
    };

    eap_result result = eap_client_set_transport(client, &transport_config);
    if (result != EAP_OK) {
        LOGE("flutter_eap_create_with_transport: eap_client_set_transport failed (%d)", result);
        return NULL;
    }

    // Check if background thread is running
    bool bg_running = eap_client_is_background_running(client);
    LOGD("flutter_eap_create_with_transport: Transport configured successfully (client=%p, ctx=%p, bg_thread_running=%d)", client, ctx, bg_running);
    return client;
}

void flutter_eap_set_kotlin_transport(eap_client* client, void* jni_env, void* kotlin_callback_obj) {
    if (!client || !jni_env || !kotlin_callback_obj) {
        LOGE("flutter_eap_set_kotlin_transport: Invalid parameters");
        return;
    }

    JNIEnv* env = (JNIEnv*)jni_env;
    jobject callback = (jobject)kotlin_callback_obj;

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGE("flutter_eap_set_kotlin_transport: No context found for client");
        return;
    }

    // Get JavaVM from JNIEnv
    if ((*env)->GetJavaVM(env, &ctx->jvm) != JNI_OK) {
        LOGE("flutter_eap_set_kotlin_transport: Failed to get JavaVM");
        return;
    }

    // Create global reference to callback object (so it survives across JNI calls)
    ctx->kotlin_callback = (*env)->NewGlobalRef(env, callback);
    if (!ctx->kotlin_callback) {
        LOGE("flutter_eap_set_kotlin_transport: Failed to create global reference");
        return;
    }

    // Get method IDs
    jclass callbackClass = (*env)->GetObjectClass(env, ctx->kotlin_callback);
    
    // fun read(buffer: ByteArray, timeout: Int): Int
    ctx->read_method = (*env)->GetMethodID(env, callbackClass, "read", "([BI)I");
    if (!ctx->read_method) {
        LOGE("flutter_eap_set_kotlin_transport: Failed to find read method");
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        (*env)->DeleteLocalRef(env, callbackClass);
        ctx->kotlin_callback = NULL;
        return;
    }
    
    // fun write(data: ByteArray): Int
    ctx->write_method = (*env)->GetMethodID(env, callbackClass, "write", "([B)I");
    if (!ctx->write_method) {
        LOGE("flutter_eap_set_kotlin_transport: Failed to find write method");
        (*env)->DeleteGlobalRef(env, ctx->kotlin_callback);
        (*env)->DeleteLocalRef(env, callbackClass);
        ctx->kotlin_callback = NULL;
        return;
    }

    // fun isDeviceConnected(): Boolean
    ctx->is_device_connected_method = (*env)->GetMethodID(env, callbackClass, "isDeviceConnected", "()Z");
    if (!ctx->is_device_connected_method) {
        LOGE("flutter_eap_set_kotlin_transport: Failed to find isDeviceConnected method");
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
            LOGD("flutter_eap_set_kotlin_transport: Pre-allocated %d-byte read buffer", READ_BUFFER_SIZE);
        } else {
            LOGE("flutter_eap_set_kotlin_transport: Failed to pre-allocate read buffer (will fall back to per-call allocation)");
            ctx->read_buffer = NULL;
            ctx->read_buffer_size = 0;
        }
    }

    LOGD("flutter_eap_set_kotlin_transport: Kotlin transport callbacks registered successfully (read + write + isDeviceConnected)");
}

bool flutter_eap_is_initialized(void) {
    return g_context != NULL;
}

eap_client* flutter_eap_get_instance(void) {
    return eap_client_get_instance();
}

int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks) {
    if (!client || !callbacks) {
        LOGE("flutter_eap_set_callbacks: NULL parameters");
        return -1;
    }

    // Get or create bridge context
    bridge_context* ctx = get_context_for_client(client);
    if (ctx == NULL) {
        // Context doesn't exist yet - create it (transport hasn't been set)
        ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
        if (!ctx) {
            LOGE("flutter_eap_set_callbacks: Failed to allocate context");
            return -1;
        }

        // Initialize callback mutex (protects dart_callbacks during hot restart swap)
        pthread_mutex_init(&ctx->callback_mutex, NULL);

        // Initialize state
        ctx->jvm = NULL;
        ctx->kotlin_callback = NULL;
        ctx->read_method = NULL;
        ctx->write_method = NULL;
        ctx->is_device_connected_method = NULL;
        ctx->read_buffer = NULL;
        ctx->read_buffer_size = 0;
        ctx->write_buffer = NULL;
        ctx->write_buffer_size = 0;
        ctx->client = client;

        register_client_context(client, ctx);
        LOGD("flutter_eap_set_callbacks: Created new context for client %p", client);
    }

    // Copy Dart callbacks to context (mutex-protected for hot restart safety)
    pthread_mutex_lock(&ctx->callback_mutex);
    memcpy(&ctx->dart_callbacks, callbacks, sizeof(flutter_eap_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    // Set message callbacks on the client
    eap_callback_config callback_config = {
        .on_gaze = on_gaze_adapter,
        .on_positioning = on_positioning_adapter,
        .on_version = on_version_adapter,
        .on_control = on_control_adapter,
        .on_calibration_point = on_calibration_point_adapter,
        .on_calibration_progress = on_calibration_progress_adapter,
        .on_calibration_paused = on_calibration_paused_adapter,
        .on_calibration_finished = on_calibration_finished_adapter,
        .on_video = on_video_adapter,
        .on_file_status = on_file_status_adapter,
        .on_logging = on_logging_adapter,
        .on_state_change = on_state_change_adapter,
        .on_error = on_error_adapter,
        .user_data = ctx  // Pass bridge context as user data for callbacks
    };

    eap_result result = eap_client_set_callbacks(client, &callback_config);
    if (result != EAP_OK) {
        LOGE("flutter_eap_set_callbacks: eap_client_set_callbacks failed (%d)", result);
        return (int)result;
    }

    LOGD("flutter_eap_set_callbacks: Callbacks registered successfully for client %p", client);
    LOGD("flutter_eap_set_callbacks: Callbacks registered:");
    LOGD("  on_gaze: %p", (void*)ctx->dart_callbacks.on_gaze);
    LOGD("  on_positioning: %p", (void*)ctx->dart_callbacks.on_positioning);
    LOGD("  on_state_change: %p", (void*)ctx->dart_callbacks.on_state_change);
    LOGD("  user_data: %p", ctx->dart_callbacks.user_data);
    return 0;
}

void flutter_eap_clear_callbacks(eap_client* client) {
    if (!client) {
        return;
    }

    LOGD("flutter_eap_clear_callbacks: Clearing callbacks for client %p", client);

    // Get context from map
    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGD("flutter_eap_clear_callbacks: No context found, nothing to clear");
        return;
    }

    // Zero the Dart callback pointers under the mutex first so any adapter
    // currently dispatching observes the change atomically.
    pthread_mutex_lock(&ctx->callback_mutex);
    memset(&ctx->dart_callbacks, 0, sizeof(flutter_eap_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    // Also unregister our C adapters from eap_client so eap_process_message
    // does not even reach them. Belt-and-suspenders against the case where
    // the Dart NativeCallable has been closed without our destroy() running -
    // e.g. engine teardown racing with an in-flight read on the I/O thread.
    // A later flutter_eap_set_callbacks call (hot restart / second create())
    // will re-register these adapters, so this is safe to do unconditionally.
    eap_callback_config empty_config = {0};
    eap_client_set_callbacks(client, &empty_config);

    LOGD("flutter_eap_clear_callbacks: Callbacks cleared successfully");
}

void flutter_eap_destroy(eap_client* client) {
    if (!client) {
        return;
    }

    LOGD("flutter_eap_destroy: Starting destruction for client %p", client);

    // Clear Dart callbacks first to prevent any stray invocations
    flutter_eap_clear_callbacks(client);

    // Get context from map
    bridge_context* ctx = get_context_for_client(client);

    // Also clear the C-level adapter callbacks before destroying
    // (safe since we're about to stop all threads anyway)
    eap_callback_config empty_config = {0};
    eap_client_set_callbacks(client, &empty_config);

    // Destroy client (this stops background thread and waits for it)
    eap_client_destroy(client);

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

        free(ctx->calib_left_copy);
        free(ctx->calib_right_copy);
        pthread_mutex_destroy(&ctx->callback_mutex);
    }

    // Unregister from map
    unregister_client_context(client);

    // Free context
    if (ctx) {
        free(ctx);
    }

    LOGD("flutter_eap_destroy: Client destroyed");
}

int flutter_eap_connect(eap_client* client) {
    if (!client) {
        return -1;
    }

    // Check current state
    eap_connection_state current_state = eap_client_get_state(client);
    LOGD("flutter_eap_connect: Current state: %d", (int)current_state);

    // If not disconnected, reset state first
    if (current_state != EAP_STATE_DISCONNECTED) {
        LOGD("flutter_eap_connect: Client not in DISCONNECTED state (%d), resetting...", (int)current_state);
        eap_client_disconnect(client);
        current_state = eap_client_get_state(client);
        LOGD("flutter_eap_connect: State after reset: %d", (int)current_state);
    }

    // eap_client_connect will start background thread if needed
    // Connect to device (background thread will handle handshake automatically)
    eap_result result = eap_client_connect(client);
    if (result != EAP_OK) {
        LOGE("flutter_eap_connect: Connect failed (%d)", result);
        return result;
    }

    LOGD("flutter_eap_connect: Connected - background thread handles all I/O automatically");
    return 0;
}

int flutter_eap_disconnect(eap_client* client) {
    if (!client) {
        return -1;
    }

    // Stop background thread first
    eap_result bg_result = eap_client_stop_background(client);
    if (bg_result != EAP_OK) {
        LOGD("flutter_eap_disconnect: Background thread stop result: %d (may already be stopped)", bg_result);
    }

    // Disconnect client
    eap_result result = eap_client_disconnect(client);

    LOGD("flutter_eap_disconnect: Disconnected");
    return result;
}

int flutter_eap_enable_gaze(eap_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_enable_gaze(client, enable);
    LOGD("flutter_eap_enable_gaze: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_enable_positioning(eap_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_enable_positioning(client, enable);
    LOGD("flutter_eap_enable_positioning: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_request_version(eap_client* client) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_request_version(client);
    LOGD("flutter_eap_request_version: Requested (%d)", result);
    return result;
}

int flutter_eap_enable_control(eap_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_enable_control(client, enable);
    LOGD("flutter_eap_enable_control: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_send_control(eap_client* client, const eap_control_message* message) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_send_control(client, message);
    LOGD("flutter_eap_send_control: (%d)", result);
    return result;
}

int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info) {
    if (!client || !info) {
        return -1;
    }

    eap_result result = eap_client_send_display_info(client, info);
    LOGD("flutter_eap_send_display_info: %ux%upx %.1fx%.1fmm (%d)",
         info->resolution.width, info->resolution.height,
         info->size_mm.width, info->size_mm.height, result);
    return result;
}

int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_start_calibration(client, config);
    LOGD("flutter_eap_start_calibration: (%d)", result);
    return result;
}

int flutter_eap_collect_calibration_points(eap_client* client) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_collect_calibration_points(client);
    LOGD("flutter_eap_collect_calibration_points: (%d)", result);
    return result;
}

int flutter_eap_abort_calibration(eap_client* client) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_abort_calibration(client);
    LOGD("flutter_eap_abort_calibration: (%d)", result);
    return result;
}

int flutter_eap_enable_video(eap_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_enable_video(client, enable);
    LOGD("flutter_eap_enable_video: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_enable_logging(eap_client* client, bool enable) {
    if (!client) {
        return -1;
    }

    eap_result result = eap_client_enable_logging(client, enable);
    LOGD("flutter_eap_enable_logging: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

// flutter_eap_feed_usb_data() is NO LONGER NEEDED
// The C library now calls transport_read() which directly calls Kotlin's read() via JNI
// No intermediate buffering required

int flutter_eap_get_state(eap_client* client) {
    if (!client) {
        return -1;
    }

    return (int)eap_client_get_state(client);
}

const char* flutter_eap_get_last_error(eap_client* client) {
    if (!client) {
        return NULL;
    }

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        return NULL;
    }

    return ctx->last_error[0] != '\0' ? ctx->last_error : NULL;
}

// =============================================================================
// Helper function to retrieve pending write data for Kotlin
// =============================================================================

// REMOVED: getPendingWrite and clearPendingWrite
// Now using direct JNI callbacks - C calls Kotlin's write() method directly

// =============================================================================
// File Transfer Functions
// =============================================================================

int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash) {
    if (!client || !path || !data) return -1;
    eap_result result = eap_client_upload_file(client, path, data, data_len, sha256_hash);
    LOGD("flutter_eap_upload_file: path=%s, size=%u (%d)", path, data_len, result);
    return result;
}

int flutter_eap_cancel_upload(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_cancel_upload(client);
    LOGD("flutter_eap_cancel_upload: (%d)", result);
    return result;
}

void flutter_eap_free(void* ptr) {
    free(ptr);
}
