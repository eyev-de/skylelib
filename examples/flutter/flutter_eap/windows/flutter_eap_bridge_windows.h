/**
 * @file flutter_eap_bridge_windows.h
 * @brief FFI bridge between Dart and C eap_client library for Windows
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart (same symbols as Apple/Android bridges)
 * - Callback registration for Dart function pointers
 * - LibUSB transport setup for USB communication with Skyle device
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_EAP_BRIDGE_WINDOWS_H
#define FLUTTER_EAP_BRIDGE_WINDOWS_H

#include <stdint.h>
#include <stdbool.h>
#include <eap_client.h>

#ifdef __cplusplus
extern "C" {
#endif

/* =========================================================================
 * Dart FFI Callback Function Pointer Types
 * Same as Apple/Android bridges - passing complete C structs by value
 * ========================================================================= */

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

typedef void (*dart_logging_callback)(
    uint8_t level,
    const char* message,
    int64_t timestamp_ms,
    void* user_data
);

typedef void (*dart_error_callback)(
    const char* error_message,
    void* user_data
);

/* =========================================================================
 * Callback Registration Structure
 * ========================================================================= */

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

/* =========================================================================
 * Public API Functions (same symbols as Apple/Android bridges for Dart FFI)
 * ========================================================================= */

/**
 * Get or create the singleton EAP client and configure transport
 * @return Pointer to eap_client, or NULL on error
 */
eap_client* flutter_eap_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart vs fresh start.
 * Call BEFORE flutter_eap_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
bool flutter_eap_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * @return Pointer to eap_client, or NULL on error
 */
eap_client* flutter_eap_get_instance(void);

/**
 * Set message callbacks on the singleton client (called from Dart FFI)
 * @param client Client pointer
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * @param client Client pointer
 */
void flutter_eap_clear_callbacks(eap_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer
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

int flutter_eap_enable_gaze(eap_client* client, bool enable);
int flutter_eap_enable_positioning(eap_client* client, bool enable);
int flutter_eap_request_version(eap_client* client);
int flutter_eap_enable_control(eap_client* client, bool enable);
int flutter_eap_send_control(eap_client* client, const eap_control_message* message);
int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info);
int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config);
int flutter_eap_collect_calibration_points(eap_client* client);
int flutter_eap_abort_calibration(eap_client* client);
int flutter_eap_enable_video(eap_client* client, bool enable);
int flutter_eap_enable_logging(eap_client* client, bool enable);
int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);
int flutter_eap_cancel_upload(eap_client* client);
int flutter_eap_get_state(eap_client* client);
const char* flutter_eap_get_last_error(eap_client* client);

/**
 * Free memory allocated by the C bridge (CRT heap).
 * On Windows, Dart's package:ffi malloc uses CoTaskMemAlloc/CoTaskMemFree
 * which is a DIFFERENT heap than the CRT malloc/free used by C code.
 * Dart MUST call this instead of malloc.free() for any pointer allocated
 * by the bridge (e.g. video pixel data copies, strdup'd error messages).
 *
 * @param ptr Pointer allocated by the bridge via malloc/_strdup
 */
void flutter_eap_free(void* ptr);

/* =========================================================================
 * Windows-specific Transport Setup
 * ========================================================================= */

/**
 * Configure USB transport for Windows (convenience function)
 * Creates a USB transport and sets it on the client.
 *
 * @param client Client pointer from flutter_eap_get_instance()
 * @param vendor_id USB vendor ID (e.g., 0x3729)
 * @param product_id USB product ID (e.g., 0x7333)
 * @return 0 on success, negative error code on failure
 */
int flutter_eap_configure_usb_transport(eap_client* client, uint16_t vendor_id, uint16_t product_id);

#ifdef __cplusplus
}
#endif

#endif  /* FLUTTER_EAP_BRIDGE_WINDOWS_H */
