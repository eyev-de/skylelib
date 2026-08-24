/**
 * @file flutter_skyle_bridge.h
 * @brief FFI bridge between Dart and C skyle_client library for Android
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart
 * - Callback registration for Dart function pointers
 * - USB data feeding from Android USB Host API
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_SKYLE_BRIDGE_H
#define FLUTTER_SKYLE_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <skyle_client.h>

// Shared multi-engine subscriber fan-out (all pull-mode platforms). Single
// source of truth for the Dart callback typedefs, the flutter_skyle_callbacks
// struct, FLUTTER_SKYLE_MAX_SUBSCRIBERS, and the add/remove export contracts;
// this bridge defines the exported wrappers around it.
#include "flutter_skyle_fanout.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Public API Functions
// =============================================================================

// =============================================================================
// Functions for Kotlin/JNI (Transport Configuration)
// =============================================================================

/**
 * Get or create the singleton EAP client and configure transport
 * Called from Kotlin layer to set up USB transport
 * 
 * The bridge provides the transport functions that use circular buffers.
 * Kotlin feeds USB data via flutter_skyle_feed_usb_data().
 * 
 * This can be called before or after setting callbacks - it's the same client instance.
 * 
 * @return Pointer to skyle_client, or NULL on error
 */
skyle_client* flutter_skyle_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart: returns true if a previous Dart VM lifecycle
 * set up the bridge, false on a truly fresh start.
 * Call BEFORE flutter_skyle_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
bool flutter_skyle_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * Returns the same client instance regardless of whether transport or callbacks
 * have been configured yet.
 *
 * @return Pointer to skyle_client, or NULL on error
 */
skyle_client* flutter_skyle_get_instance(void);

// =============================================================================
// Functions for Dart FFI (Message Callbacks)
// =============================================================================

/**
 * Set message callbacks on the singleton client
 * Called from Dart layer to set up message handlers
 * 
 * This can be called before or after setting transport - it's the same client instance.
 * 
 * @param client Client pointer from flutter_skyle_get_instance() or flutter_skyle_create_with_transport()
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_set_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks);

// flutter_skyle_add_callbacks / flutter_skyle_add_callbacks_engine /
// flutter_skyle_remove_callbacks (multi-engine fan-out) are declared in
// flutter_skyle_fanout.h and defined in flutter_skyle_bridge.c. On Android the
// stale-subscriber reaping stays with the Kotlin plugin (reportSubscriberHandle
// -> onDetachedFromEngine), so Dart uses the plain add.

/**
 * Mark the transport as owned by the Kotlin host (accessibility service).
 * While owned, flutter_skyle_destroy() and flutter_skyle_disconnect() called from
 * Dart become logged no-ops, and flutter_skyle_connect() only acts when the
 * client is in SKYLE_STATE_DISCONNECTED. This protects the shared link from
 * per-engine teardown paths.
 */
void flutter_skyle_set_host_owned(bool owned);

/**
 * Set Kotlin USB transport callbacks (called from JNI)
 * @param client Client pointer
 * @param env JNI environment
 * @param callback Kotlin callback object with read() and write() methods
 */
void flutter_skyle_set_kotlin_transport(skyle_client* client, void* env, void* callback);

/**
 * Set the Kotlin USB ownership listener (called from JNI) and register the
 * bridge's trampoline with the Skyle Link supervisor
 * (skyle_link_set_usb_ownership_callback). The listener object must implement
 *   fun onUsbOwnershipChanged(wanted: Boolean)
 * wanted=true: the supervisor acquired ownership - open/claim the USB device;
 * wanted=false: it released (handover/preempt/disable) - close/release.
 * Fires on supervisor threads: the Kotlin side must hop to a handler for the
 * USB work and never block. NULL clears both the listener and the supervisor
 * callback slot.
 *
 * @param env JNI environment
 * @param listener Kotlin listener object (NULL clears)
 */
void flutter_skyle_set_kotlin_usb_ownership_listener(void* env, void* listener);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * 
 * This is critical for hot restart: clears callbacks so the native background
 * thread doesn't try to invoke stale Dart function pointers.
 * 
 * @param client Client pointer
 */
void flutter_skyle_clear_callbacks(skyle_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer from flutter_skyle_create_with_transport()
 */
void flutter_skyle_destroy(skyle_client* client);

/**
 * Connect and start background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_connect(skyle_client* client);

/**
 * Disconnect and stop background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_disconnect(skyle_client* client);

/**
 * Enable/disable gaze streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_enable_gaze(skyle_client* client, bool enable);

/**
 * Enable/disable positioning streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_enable_positioning(skyle_client* client, bool enable);

/**
 * Request device version
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_request_version(skyle_client* client);

/**
 * Enable/disable control stream
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_enable_control(skyle_client* client, bool enable);

/**
 * Send control message
 * @param client Client pointer
 * @param message Control message
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_send_control(skyle_client* client, const skyle_control_message* message);

/**
 * Send display info (resolution in pixels + physical size in mm).
 * App -> Device, fire-and-forget.
 * @param client Client pointer
 * @param info Display info
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_send_display_info(skyle_client* client, const skyle_set_display_info* info);

/**
 * Start calibration
 * @param client Client pointer
 * @param config Calibration configuration
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_start_calibration(skyle_client* client, const skyle_calibration_config* config);

/**
 * Signal ready for next calibration point
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_collect_calibration_points(skyle_client* client);

/**
 * Abort calibration
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_abort_calibration(skyle_client* client);

/**
 * Enable/disable video streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_enable_video(skyle_client* client, bool enable);

/**
 * Enable/disable device log streaming.
 * When enabled, device pushes log lines via the on_logging callback.
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_enable_logging(skyle_client* client, bool enable);

// File transfer
int flutter_skyle_upload_file(skyle_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);

/// Cancel a file upload in progress
int flutter_skyle_cancel_upload(skyle_client* client);

// flutter_skyle_feed_usb_data() REMOVED
// No longer needed - C library calls Kotlin's read() directly via JNI

/**
 * Get current connection state
 * @param client Client pointer
 * @return Current state as int (cast to eap_state enum)
 */
int flutter_skyle_get_state(skyle_client* client);

/**
 * Get last error message
 * @param client Client pointer
 * @return Null-terminated error string or NULL if no error
 */
const char* flutter_skyle_get_last_error(skyle_client* client);

// REMOVED: getPendingWrite and clearPendingWrite - now using direct JNI callbacks

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_SKYLE_BRIDGE_H
