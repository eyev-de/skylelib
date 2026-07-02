/**
 * @file flutter_eap_bridge_apple.h
 * @brief FFI bridge between Dart and C eap_client library for Apple platforms (iOS/macOS)
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart (same symbols as Android bridge)
 * - Callback registration for Dart function pointers
 * - Transport setup via C function pointers (Swift-callable on iOS, IOKit on macOS)
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_EAP_BRIDGE_APPLE_H
#define FLUTTER_EAP_BRIDGE_APPLE_H

#include <TargetConditionals.h>
#include <stdint.h>
#include <stdbool.h>
#include <eap_client.h>

// Keep symbols reachable from Dart FFI: the linker only sees the 5 functions
// referenced from Swift, so -dead_strip removes the rest in Release. The
// `used` attribute forces emission, `visibility("default")` keeps them
// externally resolvable via DynamicLibrary.process() at runtime.
#if defined(__GNUC__) || defined(__clang__)
#define EAP_EXPORT __attribute__((used)) __attribute__((visibility("default")))
#else
#define EAP_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Dart FFI Callback Function Pointer Types
// Same as Android bridge - passing complete C structs by value
// =============================================================================

typedef void (*dart_gaze_callback)(
    eap_gaze_response gaze,
    void* user_data
);

typedef void (*dart_positioning_callback)(
    eap_positioning_response positioning,
    void* user_data
);

typedef void (*dart_version_callback)(
    eap_version_response version,
    void* user_data
);

typedef void (*dart_control_callback)(
    eap_control_message control,
    void* user_data
);

typedef void (*dart_calibration_point_callback)(
    eap_next_calibration_point point,
    void* user_data
);

typedef void (*dart_calibration_progress_callback)(
    eap_collecting_calibration_points progress,
    void* user_data
);

typedef void (*dart_calibration_paused_callback)(
    void* user_data
);

typedef void (*dart_calibration_finished_callback)(
    eap_finished_calibration result,
    void* user_data
);

typedef void (*dart_state_callback)(
    int state,
    void* user_data
);

typedef void (*dart_video_callback)(
    const uint8_t* data,
    uint32_t length,
    uint16_t width,
    uint16_t height,
    uint8_t channels,
    void* user_data
);

typedef void (*dart_file_status_callback)(
    uint16_t status,
    uint16_t progress,
    const char* error_message,
    void* user_data
);

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
    void* user_data;
} flutter_eap_callbacks;

// =============================================================================
// Public API Functions (same symbols as Android bridge for Dart FFI)
// =============================================================================

/**
 * Get or create the singleton EAP client and configure transport
 * @return Pointer to eap_client, or NULL on error
 */
EAP_EXPORT eap_client* flutter_eap_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart vs fresh start.
 * Call BEFORE flutter_eap_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
EAP_EXPORT bool flutter_eap_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * @return Pointer to eap_client, or NULL on error
 */
EAP_EXPORT eap_client* flutter_eap_get_instance(void);

/**
 * Set message callbacks on the singleton client (called from Dart FFI)
 * @param client Client pointer
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * @param client Client pointer
 */
EAP_EXPORT void flutter_eap_clear_callbacks(eap_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer
 */
EAP_EXPORT void flutter_eap_destroy(eap_client* client);

/**
 * Connect and start background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_connect(eap_client* client);

/**
 * Disconnect and stop background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_disconnect(eap_client* client);

EAP_EXPORT int flutter_eap_enable_gaze(eap_client* client, bool enable);
EAP_EXPORT int flutter_eap_enable_positioning(eap_client* client, bool enable);
EAP_EXPORT int flutter_eap_request_version(eap_client* client);
EAP_EXPORT int flutter_eap_enable_control(eap_client* client, bool enable);
EAP_EXPORT int flutter_eap_send_control(eap_client* client, const eap_control_message* message);
EAP_EXPORT int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info);
EAP_EXPORT int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config);
EAP_EXPORT int flutter_eap_collect_calibration_points(eap_client* client);
EAP_EXPORT int flutter_eap_abort_calibration(eap_client* client);
EAP_EXPORT int flutter_eap_enable_video(eap_client* client, bool enable);
EAP_EXPORT int flutter_eap_enable_logging(eap_client* client, bool enable);
EAP_EXPORT int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);
EAP_EXPORT int flutter_eap_cancel_upload(eap_client* client);
EAP_EXPORT int flutter_eap_get_state(eap_client* client);
EAP_EXPORT const char* flutter_eap_get_last_error(eap_client* client);

/**
 * Free memory allocated by the bridge (e.g. deep-copied calibration arrays,
 * video frame buffers). Safe to attach as a NativeFinalizer from Dart.
 */
EAP_EXPORT void flutter_eap_free(void* ptr);

// =============================================================================
// Apple-specific Transport Setup
// =============================================================================

/**
 * Set transport callbacks from Swift (iOS) or C (macOS)
 * Called from platform layer to provide read/write/device_check functions
 *
 * @param client Client pointer from flutter_eap_get_instance()
 * @param read_fn Transport read function (blocking, called from C background thread)
 * @param write_fn Transport write function
 * @param device_check_fn Device presence check function (can be NULL)
 * @param user_data Passed to all transport callbacks
 */
EAP_EXPORT void flutter_eap_set_apple_transport(
    eap_client* client,
    eap_transport_read_fn read_fn,
    eap_transport_write_fn write_fn,
    eap_usb_device_check_fn device_check_fn,
    void* user_data
);

#if TARGET_OS_OSX
/**
 * Configure IOKit USB transport for macOS (convenience function)
 * Creates an IOKit transport and sets it on the client.
 *
 * @param client Client pointer from flutter_eap_get_instance()
 * @param vendor_id USB vendor ID (e.g., 0x3729)
 * @param product_id USB product ID (e.g., 0x7333)
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_configure_iokit_transport(eap_client* client, uint16_t vendor_id, uint16_t product_id);
#endif

#if TARGET_OS_IOS
// =============================================================================
// iOS Push-Based Transport (no background read thread)
// =============================================================================

/**
 * Configure push-based transport for iOS.
 * Sets write callback without starting background I/O thread.
 * Use with flutter_eap_process_data() and flutter_eap_tick().
 *
 * @param client Client pointer from flutter_eap_get_instance()
 * @param write_fn Transport write function (called by C to send data)
 * @param device_check_fn Device presence check (can be NULL)
 * @param user_data Passed to callbacks
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_configure_push_transport(eap_client* client,
    eap_transport_write_fn write_fn,
    eap_usb_device_check_fn device_check_fn,
    void* user_data);

/**
 * Feed received data from iOS ExternalAccessory stream for parsing.
 * Call this from Swift StreamDelegate when raw bytes arrive.
 *
 * @param client Client pointer
 * @param data Raw bytes from EASession input stream
 * @param length Number of bytes
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_process_data(eap_client* client,
    const uint8_t* data, uint16_t length);

/**
 * Periodic tick for heartbeats and timeout detection.
 * Call from Swift timer (~every 200ms).
 *
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
EAP_EXPORT int flutter_eap_tick(eap_client* client);
#endif

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_EAP_BRIDGE_APPLE_H
