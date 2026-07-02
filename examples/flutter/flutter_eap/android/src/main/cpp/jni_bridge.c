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

#include "flutter_eap_bridge.h"

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
Java_de_eyev_flutter_1eap_EapClientJni_getInstance(
    JNIEnv* env,
    jobject obj
) {
    (void)env; // Unused
    (void)obj; // Unused

    LOGD("getInstance: Getting singleton client instance");
    eap_client* client = flutter_eap_get_instance();
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
Java_de_eyev_flutter_1eap_EapClientJni_createWithTransport(
    JNIEnv* env,
    jobject obj
) {
    (void)env; // Unused
    (void)obj; // Unused

    LOGD("createWithTransport: Configuring transport on singleton client");
    eap_client* client = flutter_eap_create_with_transport();
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
Java_de_eyev_flutter_1eap_EapClientJni_setUsbWriteCallback(
    JNIEnv* env,
    jobject obj,
    jlong client_ptr,
    jobject callback
) {
    eap_client* client = (eap_client*)(uintptr_t)client_ptr;
    if (!client || !callback) {
        LOGE("setUsbWriteCallback: Invalid parameters");
        return;
    }

    // Store global reference to callback object
    // We'll implement the actual callback storage in the bridge
    LOGD("setUsbWriteCallback: Registering Kotlin USB write callback");
    
    // Call bridge function to set up transport with Kotlin callback
    flutter_eap_set_kotlin_transport(client, env, callback);
}

/**
 * Clear Dart callbacks on the bridge context.
 * Called from onDetachedFromEngine so the C background thread cannot invoke
 * a closed NativeCallable after the Dart VM tears down.
 */
JNIEXPORT void JNICALL
Java_de_eyev_flutter_1eap_EapClientJni_clearCallbacks(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr
) {
    (void)env;
    (void)obj;
    if (clientPtr == 0) return;
    eap_client* client = (eap_client*)(uintptr_t)clientPtr;
    flutter_eap_clear_callbacks(client);
    LOGD("clearCallbacks: Dart callbacks cleared");
}

/**
 * Get current connection state
 */
JNIEXPORT jint JNICALL
Java_de_eyev_flutter_1eap_EapClientJni_getState(
    JNIEnv* env,
    jobject obj,
    jlong clientPtr
) {
    (void)env; // Unused
    (void)obj; // Unused

    if (clientPtr == 0) {
        return -1;
    }

    eap_client* client = (eap_client*)(uintptr_t)clientPtr;
    return flutter_eap_get_state(client);
}
