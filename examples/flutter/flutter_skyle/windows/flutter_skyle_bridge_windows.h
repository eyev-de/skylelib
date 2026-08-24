/**
 * @file flutter_skyle_bridge_windows.h
 * @brief FFI bridge between Dart and C skyle_client library for Windows
 *
 * This bridge provides:
 * - FFI-friendly function exports for Dart (same symbols as Apple/Android bridges)
 * - Callback registration for Dart function pointers
 * - LibUSB transport setup for USB communication with Skyle device
 * - Direct callback invocation from C to Dart (no MethodChannel)
 */

#ifndef FLUTTER_SKYLE_BRIDGE_WINDOWS_H
#define FLUTTER_SKYLE_BRIDGE_WINDOWS_H

#include <stdint.h>
#include <stdbool.h>
#include <skyle_client.h>

#ifdef __cplusplus
extern "C" {
#endif

/* =========================================================================
 * Callback types + registration
 *
 * Windows runs the shared multi-engine subscriber fan-out: the callback
 * typedefs, the flutter_skyle_callbacks struct, and the add/remove export
 * contracts come from the shared module header (single source of truth for
 * the Dart-shared ABI); this bridge defines the exported wrappers in
 * flutter_skyle_bridge_windows.c.
 * ========================================================================= */

#include "../native/fanout/flutter_skyle_fanout.h"

/* =========================================================================
 * Public API Functions (same symbols as Apple/Android bridges for Dart FFI)
 * ========================================================================= */

/**
 * Get or create the singleton EAP client and configure transport
 * @return Pointer to skyle_client, or NULL on error
 */
skyle_client* flutter_skyle_create_with_transport(void);

/**
 * Check if the bridge has been initialized (client + context exist)
 * Use this to detect hot restart vs fresh start.
 * Call BEFORE flutter_skyle_get_instance() since that creates on demand.
 *
 * @return true if bridge context exists, false otherwise
 */
bool flutter_skyle_is_initialized(void);

/**
 * Get the singleton EAP client instance
 * @return Pointer to skyle_client, or NULL on error
 */
skyle_client* flutter_skyle_get_instance(void);

/**
 * Set message callbacks on the singleton client (called from Dart FFI)
 * @param client Client pointer
 * @param callbacks Structure containing all Dart callback function pointers
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_set_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks);

/**
 * Clear all Dart callbacks (MUST call before closing NativeCallable objects)
 * @param client Client pointer
 */
void flutter_skyle_clear_callbacks(skyle_client* client);

/**
 * Destroy EAP client and free resources
 * @param client Client pointer
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

int flutter_skyle_enable_gaze(skyle_client* client, bool enable);
int flutter_skyle_enable_positioning(skyle_client* client, bool enable);
int flutter_skyle_request_version(skyle_client* client);
int flutter_skyle_enable_control(skyle_client* client, bool enable);
int flutter_skyle_send_control(skyle_client* client, const skyle_control_message* message);
int flutter_skyle_send_display_info(skyle_client* client, const skyle_set_display_info* info);
int flutter_skyle_start_calibration(skyle_client* client, const skyle_calibration_config* config);
int flutter_skyle_collect_calibration_points(skyle_client* client);
int flutter_skyle_abort_calibration(skyle_client* client);
int flutter_skyle_enable_video(skyle_client* client, bool enable);
int flutter_skyle_enable_logging(skyle_client* client, bool enable);
int flutter_skyle_upload_file(skyle_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash);
int flutter_skyle_cancel_upload(skyle_client* client);
int flutter_skyle_get_state(skyle_client* client);
const char* flutter_skyle_get_last_error(skyle_client* client);

/**
 * Free memory allocated by the C bridge (CRT heap).
 * On Windows, Dart's package:ffi malloc uses CoTaskMemAlloc/CoTaskMemFree
 * which is a DIFFERENT heap than the CRT malloc/free used by C code.
 * Dart MUST call this instead of malloc.free() for any pointer allocated
 * by the bridge (e.g. video pixel data copies, strdup'd error messages).
 *
 * @param ptr Pointer allocated by the bridge via malloc/_strdup
 */
void flutter_skyle_free(void* ptr);

/* =========================================================================
 * Windows-specific Transport Setup
 * ========================================================================= */

/**
 * Configure USB transport for Windows (convenience function)
 * Creates a USB transport and sets it on the client.
 *
 * The first successful call also registers the Skyle Link USB ownership
 * callback (skyle_link_set_usb_ownership_callback): during supervisor
 * handovers the bridge destroys the WinUSB transport on release (closing the
 * OS device claim so another app can take the tracker) and recreates it with
 * the same VID/PID on reacquire.
 *
 * @param client Client pointer from flutter_skyle_get_instance()
 * @param vendor_id USB vendor ID (e.g., 0x3729)
 * @param product_id USB product ID (e.g., 0x7333)
 * @return 0 on success, negative error code on failure
 */
int flutter_skyle_configure_usb_transport(skyle_client* client, uint16_t vendor_id, uint16_t product_id);

#ifdef __cplusplus
}
#endif

#endif  /* FLUTTER_SKYLE_BRIDGE_WINDOWS_H */
