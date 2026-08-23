/**
 * Umbrella header for flutter_eap iOS module.
 *
 * Declares only the C functions needed by FlutterEapPlugin.swift.
 * The full bridge API is used by Dart FFI and compiled via the unity build file.
 */

#ifndef FLUTTER_EAP_IOS_H
#define FLUTTER_EAP_IOS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque client type (full definition in eap_client.h, compiled via unity build)
typedef struct eap_client eap_client;

// Transport function pointer types (from eap_client.h)
typedef int (*eap_transport_write_fn)(const uint8_t* data, uint16_t length, void* user_data);
typedef bool (*eap_usb_device_check_fn)(void* user_data);

/// Get the singleton EAP client instance (created by Dart FFI layer)
eap_client* flutter_eap_get_instance(void);

/// Configure push-based transport (write-only, no background thread)
int flutter_eap_configure_push_transport(eap_client* client,
    eap_transport_write_fn write_fn,
    eap_usb_device_check_fn device_check_fn,
    void* user_data);

/// Feed received data from EASession input stream for parsing
int flutter_eap_process_data(eap_client* client,
    const uint8_t* data, uint16_t length);

/// Connect (sets state to LINK_SYNCED in push mode)
int flutter_eap_connect(eap_client* client);

/// Disconnect
int flutter_eap_disconnect(eap_client* client);

/// Null out all Dart callback function pointers.
/// Call before the Dart VM closes NativeCallables to prevent the EA RunLoop
/// from invoking a stale pointer and triggering abort() in the Dart runtime.
void flutter_eap_clear_callbacks(eap_client* client);

#ifdef __cplusplus
}
#endif

#endif
