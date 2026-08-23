/**
 * Umbrella header for flutter_eap macOS module.
 *
 * Declares only the C functions needed by FlutterEapPlugin.swift.
 * The full bridge API (callbacks, transport types) is used by Dart FFI
 * and compiled via the unity build file.
 */

#ifndef FLUTTER_EAP_MACOS_H
#define FLUTTER_EAP_MACOS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque client type (full definition in eap_client.h, compiled via unity build)
typedef struct eap_client eap_client;

/// Get the singleton EAP client instance (created by Dart FFI layer)
eap_client* flutter_eap_get_instance(void);

/// Configure IOKit USB transport for macOS
/// @return 0 on success, negative error code on failure
int flutter_eap_configure_iokit_transport(eap_client* client, uint16_t vendor_id, uint16_t product_id);

/// Null out all Dart callback function pointers.
/// Call before the Dart VM closes NativeCallables to prevent the IOKit
/// background thread from invoking a stale pointer and triggering abort().
void flutter_eap_clear_callbacks(eap_client* client);

#ifdef __cplusplus
}
#endif

#endif
