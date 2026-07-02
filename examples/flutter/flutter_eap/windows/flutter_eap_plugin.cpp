#include "flutter_eap_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

extern "C" {
#include "flutter_eap_bridge_windows.h"
}

namespace flutter_eap {

// Skyle eye tracker USB identifiers
static const uint16_t kSkyleVendorId = 0x3729;
static const uint16_t kSkyleProductId = 0x7333;

bool FlutterEapPlugin::is_transport_configured_ = false;

void FlutterEapPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "flutter_eap/usb",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterEapPlugin>();

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterEapPlugin::FlutterEapPlugin() = default;

FlutterEapPlugin::~FlutterEapPlugin() {
  // Clear Dart callbacks before the Dart VM tears down NativeCallables.
  // Without this the C background thread can call a closed NativeCallable
  // and trigger DLRT_GetFfiCallbackMetadata -> abort().
  eap_client* client = flutter_eap_get_instance();
  if (client) {
    flutter_eap_clear_callbacks(client);
  }
}

void FlutterEapPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "configureTransport") {
    bool success = ConfigureTransport();
    result->Success(flutter::EncodableValue(success));
  } else {
    result->NotImplemented();
  }
}

bool FlutterEapPlugin::ConfigureTransport() {
  eap_client* client = flutter_eap_get_instance();
  if (!client) {
    return false;
  }

  // Only configure transport once (shared across engines)
  if (is_transport_configured_) {
    return true;
  }

  int config_result = flutter_eap_configure_usb_transport(
      client, kSkyleVendorId, kSkyleProductId);

  if (config_result == 0) {
    is_transport_configured_ = true;
    return true;
  }

  return false;
}

}  // namespace flutter_eap
