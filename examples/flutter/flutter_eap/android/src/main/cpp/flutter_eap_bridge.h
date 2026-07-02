/**
 * @file flutter_eap_bridge.h
 * @brief FFI bridge between Dart and C eap_client library for Android
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart
 * - Callback registration for Dart function pointers
 * - USB data feeding from Android USB Host API
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_EAP_BRIDGE_H
#define FLUTTER_EAP_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <eap_client.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Dart FFI Callback Function Pointer Types
// Now passing complete C structs instead of primitives
// =============================================================================

/**
 * Gaze data callback (struct by value)
 * @param gaze eap_gaze_response struct passed by value
 * @param user_data User data pointer passed from Dart
 */
typedef void (*dart_gaze_callback)(
    eap_gaze_response gaze,
    void* user_data
);

/**
 * Positioning data callback (struct by value)
 * @param positioning eap_positioning_response struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_positioning_callback)(
    eap_positioning_response positioning,
    void* user_data
);

/**
 * Version callback (struct by value)
 * @param version eap_version_response struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_version_callback)(
    eap_version_response version,
    void* user_data
);

/**
 * Control callback (struct by value)
 * @param control eap_control_message struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_control_callback)(
    eap_control_message control,
    void* user_data
);

/**
 * Calibration point callback (struct by value)
 * @param point eap_next_calibration_point struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_point_callback)(
    eap_next_calibration_point point,
    void* user_data
);

/**
 * Calibration progress callback (struct by value)
 * @param progress eap_collecting_calibration_points struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_progress_callback)(
    eap_collecting_calibration_points progress,
    void* user_data
);

/**
 * Calibration paused callback
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_paused_callback)(
    void* user_data
);

/**
 * Calibration finished callback (struct by value)
 * @param result eap_finished_calibration struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_finished_callback)(
    eap_finished_calibration result,
    void* user_data
);

/**
 * State change callback
 * @param state New connection state (eap_state enum value as int)
 * @param user_data User data pointer
 */
typedef void (*dart_state_callback)(
    int state,
    void* user_data
);

/**
 * Video frame callback
 * @param data Raw video frame pixel data (valid only during callback)
 * @param length Length of pixel data in bytes
 * @param width Frame width in pixels
 * @param height Frame height in pixels
 * @param channels Number of channels (1=grayscale, 3=BGR, 4=BGRA)
 * @param user_data User data pointer
 */
typedef void (*dart_video_callback)(
    const uint8_t* data,
    uint32_t length,
    uint16_t width,
    uint16_t height,
    uint8_t channels,
    void* user_data
);

/**
 * File status callback
 * @param status File transfer status (0=success, 1=progress, 2=failed)
 * @param progress Progress percentage 0-100 (valid when status==1)
 * @param error_message Error message (valid when status==2, NULL otherwise)
 * @param user_data User data pointer
 */
typedef void (*dart_file_status_callback)(
    uint16_t status,
    uint16_t progress,
    const char* error_message,
    void* user_data
);

/**
 * Error callback
 * @param error_message Null-terminated error message
 * @param user_data User data pointer
 */
typedef void (*dart_error_callback)(
    const char* error_message,
    void* user_data
);

/**
 * Logging callback — device log line streamed over EAP.
 * @param level         Log severity (eap_log_level)
 * @param message       Heap-allocated UTF-8 message string. Dart MUST free
 *                      this with flutter_eap_free() after reading.
 * @param timestamp_ms  Device timestamp (Unix ms) from the EAP message header
 * @param user_data     User data pointer
 */
typedef void (*dart_logging_callback)(
    uint8_t level,
    const char* message,
    int64_t timestamp_ms,
    void* user_data
);

// =============================================================================
// Callback Registration Structure
// =============================================================================

/**
 * Structure to hold all Dart callback function pointers
 * Passed to flutter_eap_create()
 */
typedef struct {
    dart_gaze_callback on_gaze;
    dart_positioning_callback on_positioning;
    dart_version_callback on_version;
    dart_control_callback on_control;
    dart_calibration_point_callback on_calibration_point;
    dart_calibration_progress_callback on_calibration_progress;
    dart_calibration_paused_callback on_calibration_paused;
    dart_calibration_finished_callback on_calibration_finished;
    dart_video_callback on_video;
    dart_file_status_callback on_file_status;
    dart_logging_callback on_logging;
    dart_state_callback on_state_change;
    dart_error_callback on_error;
    void* user_data;  // Passed back to all callbacks
} flutter_eap_callbacks;

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
 * Kotlin feeds USB data via flutter_eap_feed_usb_data().
 * 
 * This can be called before or after setting callbacks - it's the same client instance.
 * 
 * @return Pointer to eap_client, or NULL on error
 */
eap_client* flutter_eap_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart: returns true if a previous Dart VM lifecycle
 * set up the bridge, false on a truly fresh start.
 * Call BEFORE flutter_eap_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
bool flutter_eap_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * Returns the same client instance regardless of whether transport or callbacks
 * have been configured yet.
 *
 * @return Pointer to eap_client, or NULL on error
 */
eap_client* flutter_eap_get_instance(void);

// =============================================================================
// Functions for Dart FFI (Message Callbacks)
// =============================================================================

/**
 * Set message callbacks on the singleton client
 * Called from Dart layer to set up message handlers
 * 
 * This can be called before or after setting transport - it's the same client instance.
 * 
 * @param client Client pointer from flutter_eap_get_instance() or flutter_eap_create_with_transport()
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks);

/**
 * Set Kotlin USB transport callbacks (called from JNI)
 * @param client Client pointer
 * @param env JNI environment
 * @param callback Kotlin callback object with read() and write() methods
 */
void flutter_eap_set_kotlin_transport(eap_client* client, void* env, void* callback);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * 
 * This is critical for hot restart: clears callbacks so the native background
 * thread doesn't try to invoke stale Dart function pointers.
 * 
 * @param client Client pointer
 */
void flutter_eap_clear_callbacks(eap_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer from flutter_eap_create_with_transport()
 */
void flutter_eap_destroy(eap_client* client);

/**
 * Connect and start background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_connect(eap_client* client);

/**
 * Disconnect and stop background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_disconnect(eap_client* client);

/**
 * Enable/disable gaze streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_enable_gaze(eap_client* client, bool enable);

/**
 * Enable/disable positioning streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_enable_positioning(eap_client* client, bool enable);

/**
 * Request device version
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_request_version(eap_client* client);

/**
 * Enable/disable control stream
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_enable_control(eap_client* client, bool enable);

/**
 * Send control message
 * @param client Client pointer
 * @param message Control message
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_send_control(eap_client* client, const eap_control_message* message);

/**
 * Send display info (resolution in pixels + physical size in mm).
 * App -> Device, fire-and-forget.
 * @param client Client pointer
 * @param info Display info
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info);

/**
 * Start calibration
 * @param client Client pointer
 * @param config Calibration configuration
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config);

/**
 * Signal ready for next calibration point
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_collect_calibration_points(eap_client* client);

/**
 * Abort calibration
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_abort_calibration(eap_client* client);

/**
 * Enable/disable video streaming
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_enable_video(eap_client* client, bool enable);

/**
 * Enable/disable device log streaming.
 * When enabled, device pushes log lines via the on_logging callback.
 * @param client Client pointer
 * @param enable True to enable, false to disable
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_enable_logging(eap_client* client, bool enable);

// File transfer
int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);

/// Cancel a file upload in progress
int flutter_eap_cancel_upload(eap_client* client);

// flutter_eap_feed_usb_data() REMOVED
// No longer needed - C library calls Kotlin's read() directly via JNI

/**
 * Get current connection state
 * @param client Client pointer
 * @return Current state as int (cast to eap_state enum)
 */
int flutter_eap_get_state(eap_client* client);

/**
 * Get last error message
 * @param client Client pointer
 * @return Null-terminated error string or NULL if no error
 */
const char* flutter_eap_get_last_error(eap_client* client);

// REMOVED: getPendingWrite and clearPendingWrite - now using direct JNI callbacks

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_EAP_BRIDGE_H
