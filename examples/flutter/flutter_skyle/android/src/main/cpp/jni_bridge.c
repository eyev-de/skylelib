/**
 * @file jni_bridge.c
 * @brief JNI wrapper functions for Kotlin to call C library directly
 *
 * This allows Kotlin to bypass Dart for USB I/O, improving performance.
 * Only parsed messages flow to Dart via FFI callbacks.
 */

#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>

#include "flutter_skyle_bridge.h"
#include "flutter_skyle_link_glue.h"

#define LOG_TAG "JniBridge"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// =============================================================================
// JNI Functions called from Kotlin
// =============================================================================

/**
 * Get the singleton EAP client instance
 * Called from Kotlin to get the client pointer
 * 
 * @return Client pointer as jlong, or 0 on error
 */
JNIEXPORT jlong JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_getInstance(
    JNIEnv* env,
    jobject obj
) {
    (void)env; // Unused
    (void)obj; // Unused

    LOGD("getInstance: Getting singleton client instance");
    skyle_client* client = flutter_skyle_get_instance();
    if (client == NULL) {
        LOGE("getInstance: Failed to get client instance");
        return 0;
    }

    LOGD("getInstance: Got client instance (client=%p)", client);
    return (jlong)(uintptr_t)client;
}

/**
 * Create EAP client with transport configuration
 * Called from Kotlin to set up USB transport layer
 * 
 * @return Client pointer as jlong, or 0 on error
 */
JNIEXPORT jlong JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_createWithTransport(
    JNIEnv* env,
    jobject obj
) {
    (void)env; // Unused
    (void)obj; // Unused

    LOGD("createWithTransport: Configuring transport on singleton client");
    skyle_client* client = flutter_skyle_create_with_transport();
    if (client == NULL) {
        LOGE("createWithTransport: Failed to configure transport");
        return 0;
    }

    LOGD("createWithTransport: Transport configured successfully (client=%p)", client);
    return (jlong)(uintptr_t)client;
}

/**
 * Set Kotlin USB write callback
 * This allows C library to directly call Kotlin to send USB data
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_setUsbWriteCallback(
    JNIEnv* env,
    jobject obj,
    jlong client_ptr,
    jobject callback
) {
    skyle_client* client = (skyle_client*)(uintptr_t)client_ptr;
    if (!client || !callback) {
        LOGE("setUsbWriteCallback: Invalid parameters");
        return;
    }

    // Store global reference to callback object
    // We'll implement the actual callback storage in the bridge
    LOGD("setUsbWriteCallback: Registering Kotlin USB write callback");
    
    // Call bridge function to set up transport with Kotlin callback
    flutter_skyle_set_kotlin_transport(client, env, callback);
}

/**
 * Clear Dart callbacks on the bridge context.
 * Called from onDetachedFromEngine so the C background thread cannot invoke
 * a closed NativeCallable after the Dart VM tears down.
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_clearCallbacks(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr
) {
    (void)env;
    (void)obj;
    if (clientPtr == 0) return;
    skyle_client* client = (skyle_client*)(uintptr_t)clientPtr;
    flutter_skyle_clear_callbacks(client);
    LOGD("clearCallbacks: Dart callbacks cleared");
}

/**
 * Get current connection state
 */
JNIEXPORT jint JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_getState(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr
) {
    (void)env; // Unused
    (void)obj; // Unused

    if (clientPtr == 0) {
        return -1;
    }

    skyle_client* client = (skyle_client*)(uintptr_t)clientPtr;
    return flutter_skyle_get_state(client);
}

/**
 * Mark the transport as owned by the Kotlin host (accessibility service).
 * While owned, Dart-initiated destroy/disconnect are no-ops and connect only
 * acts from DISCONNECTED.
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_setHostOwned(
    JNIEnv* env,
    jobject obj,
    jboolean owned
) {
    (void)env;
    (void)obj;
    flutter_skyle_set_host_owned(owned == JNI_TRUE);
}

/**
 * Remove one engine's callback subscriber (fan-out slot).
 * Called from onDetachedFromEngine with the handle the engine's Dart side
 * reported, so the C dispatch thread cannot invoke a closed NativeCallable.
 * Safe with stale/unknown handles (no-op).
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_removeSubscriber(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr,
    jlong handle
) {
    (void)env;
    (void)obj;
    if (clientPtr == 0 || handle <= 0) return;
    skyle_client* client = (skyle_client*)(uintptr_t)clientPtr;
    int result = flutter_skyle_remove_callbacks(client, (int64_t)handle);
    LOGD("removeSubscriber: handle=%lld -> %d", (long long)handle, result);
}

// =============================================================================
// Skyle Link (automatic transport supervisor) JNI wrappers
// =============================================================================

/**
 * Set the Skyle Link identity (HELLO app id, priority tier, USB permission
 * state). Safe to call repeatedly - the supervisor picks the change up on its
 * next evaluation (usb_capable flips when Android grants/loses the USB
 * permission).
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_setIdentity(
    JNIEnv* env,
    jobject obj,
    jstring appId,
    jint tier,
    jboolean usbCapable
) {
    (void)obj;
    if (!appId) return;
    const char* app_id = (*env)->GetStringUTFChars(env, appId, NULL);
    if (!app_id) return;
    flutter_skyle_set_identity(app_id, (uint8_t)tier, usbCapable == JNI_TRUE);
    (*env)->ReleaseStringUTFChars(env, appId, app_id);
}

/**
 * Enable/disable the automatic transport supervisor. Enabling returns
 * immediately (the mode decision lands on the supervisor thread); disabling
 * is a deliberate stop: OWNER sends BYE(handover) + releases USB via the
 * ownership listener, CLIENT closes.
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_setSupervisorEnabled(
    JNIEnv* env,
    jobject obj,
    jboolean enabled
) {
    (void)env;
    (void)obj;
    flutter_skyle_set_supervisor_enabled(enabled == JNI_TRUE);
}

/**
 * Register the Kotlin USB ownership listener (onUsbOwnershipChanged). The
 * supervisor grants/releases USB ownership through it; fires on supervisor
 * threads. NULL clears.
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_setUsbOwnershipListener(
    JNIEnv* env,
    jobject obj,
    jobject listener
) {
    (void)obj;
    flutter_skyle_set_kotlin_usb_ownership_listener(env, listener);
}

/**
 * Disconnect the client and stop its background thread. Used by
 * SkyleUsbHost.stop() AFTER clearing host ownership (while host-owned the
 * bridge suppresses disconnects).
 */
JNIEXPORT jint JNICALL
Java_de_eyev_flutter_1skyle_SkyleClientJni_disconnect(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr
) {
    (void)env;
    (void)obj;
    if (clientPtr == 0) return -1;
    skyle_client* client = (skyle_client*)(uintptr_t)clientPtr;
    int result = flutter_skyle_disconnect(client);
    LOGD("disconnect: -> %d", result);
    return (jint)result;
}
