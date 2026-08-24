/**
 * Umbrella header for flutter_skyle iOS module.
 *
 * Declares only the C functions needed by FlutterSkylePlugin.swift.
 * The full bridge API is used by Dart FFI and compiled via the unity build file.
 */

#ifndef FLUTTER_SKYLE_IOS_H
#define FLUTTER_SKYLE_IOS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque client type (full definition in skyle_client.h, compiled via unity build)
typedef struct skyle_client skyle_client;

// Transport function pointer types (from skyle_client.h)
typedef int (*skyle_transport_write_fn)(const uint8_t* data, uint16_t length, void* user_data);
typedef bool (*skyle_usb_device_check_fn)(void* user_data);

/// Get the singleton EAP client instance (created by Dart FFI layer)
skyle_client* flutter_skyle_get_instance(void);

/// Configure push-based transport (write-only, no background thread)
int flutter_skyle_configure_push_transport(skyle_client* client,
    skyle_transport_write_fn write_fn,
    skyle_usb_device_check_fn device_check_fn,
    void* user_data);

/// Feed received data from EASession input stream for parsing
int flutter_skyle_process_data(skyle_client* client,
    const uint8_t* data, uint16_t length);

/// Connect (sets state to LINK_SYNCED in push mode)
int flutter_skyle_connect(skyle_client* client);

/// Disconnect
int flutter_skyle_disconnect(skyle_client* client);

/// Null out all Dart callback function pointers.
/// Call before the Dart VM closes NativeCallables to prevent the EA RunLoop
/// from invoking a stale pointer and triggering abort() in the Dart runtime.
void flutter_skyle_clear_callbacks(skyle_client* client);

#ifdef __cplusplus
}
#endif

#endif
