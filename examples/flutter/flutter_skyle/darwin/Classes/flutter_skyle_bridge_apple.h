/**
 * @file flutter_skyle_bridge_apple.h
 * @brief FFI bridge between Dart and C skyle_client library for Apple platforms (iOS/macOS)
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart (same symbols as Android bridge)
 * - Callback registration for Dart function pointers
 * - Transport setup via C function pointers (Swift-callable on iOS, IOKit on macOS)
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_SKYLE_BRIDGE_APPLE_H
#define FLUTTER_SKYLE_BRIDGE_APPLE_H

#include <TargetConditionals.h>
#include <stdint.h>
#include <stdbool.h>
#include <skylelib/skyle_client.h>

// Keep symbols reachable from Dart FFI: the linker only sees the 5 functions
// referenced from Swift, so -dead_strip removes the rest in Release. The
// `used` attribute forces emission, `visibility("default")` keeps them
// externally resolvable via DynamicLibrary.process() at runtime.
#if defined(__GNUC__) || defined(__clang__)
#define FLUTTER_SKYLE_EXPORT __attribute__((used)) __attribute__((visibility("default")))
#else
#define FLUTTER_SKYLE_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

#if TARGET_OS_OSX
// =============================================================================
// macOS: shared multi-engine subscriber fan-out (all pull-mode platforms).
// The callback typedefs, the flutter_skyle_callbacks struct, and the
// add/remove export contracts come from the shared module header (single
// source of truth for the Dart-shared ABI); this bridge defines the exported
// wrappers. iOS below keeps its own field-identical single-slot copy.
// =============================================================================
#include "../../native/fanout/flutter_skyle_fanout.h"
#else

// =============================================================================
// Dart FFI Callback Function Pointer Types (iOS single-slot push mode)
// Same layout as the shared fan-out module - passing complete C structs by value
// =============================================================================

typedef void (*dart_gaze_callback)(
    skyle_gaze_response gaze,
    void* user_data
);

typedef void (*dart_positioning_callback)(
    skyle_positioning_response positioning,
    void* user_data
);

typedef void (*dart_version_callback)(
    skyle_version_response version,
    void* user_data
);

typedef void (*dart_control_callback)(
    skyle_control_message control,
    void* user_data
);

typedef void (*dart_calibration_point_callback)(
    skyle_next_calibration_point point,
    void* user_data
);

typedef void (*dart_calibration_progress_callback)(
    skyle_collecting_calibration_points progress,
    void* user_data
);

typedef void (*dart_calibration_paused_callback)(
    void* user_data
);

typedef void (*dart_calibration_finished_callback)(
    skyle_finished_calibration result,
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
 * @param level         Log severity (skyle_log_level)
 * @param message       Heap-allocated UTF-8 message string. Dart MUST free
 *                      this with flutter_skyle_free() after reading.
 * @param timestamp_ms  Device timestamp (Unix ms) from the EAP message header
 * @param user_data     User data pointer
 */
typedef void (*dart_logging_callback)(
    uint8_t level,
    const char* message,
    int64_t timestamp_ms,
    void* user_data
);

/**
 * Skyle Link suspension state callback. Present for ABI parity with the Dart
 * FlutterSkyleCallbacks struct; on iOS the Skyle Link supervisor never runs, so
 * suspension events are never delivered - the field exists only so the struct
 * layout matches the fan-out platforms.
 */
typedef void (*dart_suspend_state_callback)(
    bool suspended,
    const char* holder_app_id,
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
    // Appended fields ONLY below this line: the layout above is ABI shared
    // with Dart (FlutterSkyleCallbacks) and the fan-out module - all
    // definitions must stay field-identical. Unused on iOS (see typedef).
    dart_suspend_state_callback on_suspend_state;
} flutter_skyle_callbacks;

#endif // !TARGET_OS_OSX

// =============================================================================
// Public API Functions (same symbols as Android bridge for Dart FFI)
// =============================================================================

/**
 * Get or create the singleton EAP client and configure transport
 * @return Pointer to skyle_client, or NULL on error
 */
FLUTTER_SKYLE_EXPORT skyle_client* flutter_skyle_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart vs fresh start.
 * Call BEFORE flutter_skyle_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
FLUTTER_SKYLE_EXPORT bool flutter_skyle_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * @return Pointer to skyle_client, or NULL on error
 */
FLUTTER_SKYLE_EXPORT skyle_client* flutter_skyle_get_instance(void);

/**
 * Set message callbacks on the singleton client (called from Dart FFI)
 * @param client Client pointer
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_set_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * @param client Client pointer
 */
FLUTTER_SKYLE_EXPORT void flutter_skyle_clear_callbacks(skyle_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer
 */
FLUTTER_SKYLE_EXPORT void flutter_skyle_destroy(skyle_client* client);

/**
 * Connect and start background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_connect(skyle_client* client);

/**
 * Disconnect and stop background thread
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_disconnect(skyle_client* client);

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_gaze(skyle_client* client, bool enable);
FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_positioning(skyle_client* client, bool enable);
FLUTTER_SKYLE_EXPORT int flutter_skyle_request_version(skyle_client* client);
FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_control(skyle_client* client, bool enable);
FLUTTER_SKYLE_EXPORT int flutter_skyle_send_control(skyle_client* client, const skyle_control_message* message);
FLUTTER_SKYLE_EXPORT int flutter_skyle_send_display_info(skyle_client* client, const skyle_set_display_info* info);
FLUTTER_SKYLE_EXPORT int flutter_skyle_start_calibration(skyle_client* client, const skyle_calibration_config* config);
FLUTTER_SKYLE_EXPORT int flutter_skyle_collect_calibration_points(skyle_client* client);
FLUTTER_SKYLE_EXPORT int flutter_skyle_abort_calibration(skyle_client* client);
FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_video(skyle_client* client, bool enable);
FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_logging(skyle_client* client, bool enable);
FLUTTER_SKYLE_EXPORT int flutter_skyle_upload_file(skyle_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);
FLUTTER_SKYLE_EXPORT int flutter_skyle_cancel_upload(skyle_client* client);
FLUTTER_SKYLE_EXPORT int flutter_skyle_get_state(skyle_client* client);
FLUTTER_SKYLE_EXPORT const char* flutter_skyle_get_last_error(skyle_client* client);

/**
 * Free memory allocated by the bridge (e.g. deep-copied calibration arrays,
 * video frame buffers). Safe to attach as a NativeFinalizer from Dart.
 */
FLUTTER_SKYLE_EXPORT void flutter_skyle_free(void* ptr);

// =============================================================================
// Apple-specific Transport Setup
// =============================================================================

/**
 * Set transport callbacks from Swift (iOS) or C (macOS)
 * Called from platform layer to provide read/write/device_check functions
 *
 * @param client Client pointer from flutter_skyle_get_instance()
 * @param read_fn Transport read function (blocking, called from C background thread)
 * @param write_fn Transport write function
 * @param device_check_fn Device presence check function (can be NULL)
 * @param user_data Passed to all transport callbacks
 */
FLUTTER_SKYLE_EXPORT void flutter_skyle_set_apple_transport(
    skyle_client* client,
    skyle_transport_read_fn read_fn,
    skyle_transport_write_fn write_fn,
    skyle_usb_device_check_fn device_check_fn,
    void* user_data
);

#if TARGET_OS_OSX
/**
 * Configure IOKit USB transport for macOS (convenience function)
 * Creates an IOKit transport and sets it on the client.
 *
 * The first successful call also registers the Skyle Link USB ownership
 * callback (skyle_link_set_usb_ownership_callback): during supervisor
 * handovers the bridge destroys the IOKit transport on release (closing the
 * OS device claim so another app can take the tracker) and recreates it with
 * the same VID/PID on reacquire. macOS only - iOS uses push mode without a
 * supervisor.
 *
 * @param client Client pointer from flutter_skyle_get_instance()
 * @param vendor_id USB vendor ID (e.g., 0x3729)
 * @param product_id USB product ID (e.g., 0x7333)
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_configure_iokit_transport(skyle_client* client, uint16_t vendor_id, uint16_t product_id);
#endif

#if TARGET_OS_IOS
// =============================================================================
// iOS Push-Based Transport (no background read thread)
// =============================================================================

/**
 * Configure push-based transport for iOS.
 * Sets write callback without starting background I/O thread.
 * Use with flutter_skyle_process_data() and flutter_skyle_tick().
 *
 * @param client Client pointer from flutter_skyle_get_instance()
 * @param write_fn Transport write function (called by C to send data)
 * @param device_check_fn Device presence check (can be NULL)
 * @param user_data Passed to callbacks
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_configure_push_transport(skyle_client* client,
    skyle_transport_write_fn write_fn,
    skyle_usb_device_check_fn device_check_fn,
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
FLUTTER_SKYLE_EXPORT int flutter_skyle_process_data(skyle_client* client,
    const uint8_t* data, uint16_t length);

/**
 * Periodic tick for heartbeats and timeout detection.
 * Call from Swift timer (~every 200ms).
 *
 * @param client Client pointer
 * @return 0 on success, negative error code on failure
 */
FLUTTER_SKYLE_EXPORT int flutter_skyle_tick(skyle_client* client);
#endif

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_SKYLE_BRIDGE_APPLE_H
