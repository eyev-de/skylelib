#include "flutter_skyle_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

extern "C" {
#include "flutter_skyle_bridge_windows.h"
}

namespace flutter_skyle {

// Skyle eye tracker USB identifiers
static const uint16_t kSkyleVendorId = 0x3729;
static const uint16_t kSkyleProductId = 0x7333;

bool FlutterSkylePlugin::is_transport_configured_ = false;
int FlutterSkylePlugin::instance_count_ = 0;

void FlutterSkylePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "flutter_skyle/usb",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterSkylePlugin>();

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterSkylePlugin::FlutterSkylePlugin() { ++instance_count_; }

FlutterSkylePlugin::~FlutterSkylePlugin() {
  // Each engine holds its own subscriber in the native fan-out table and
  // removes it in Dart (SkyleClientFfi.destroy). Clearing ALL callbacks here
  // would wipe the OTHER engines' subscriptions, so the safety net (an engine
  // dying without its Dart destroy must not leave the C background thread
  // calling a closed NativeCallable - DLRT_GetFfiCallbackMetadata -> abort())
  // only fires when the LAST engine's plugin instance is destroyed.
  if (--instance_count_ <= 0) {
    skyle_client* client = flutter_skyle_get_instance();
    if (client) {
      flutter_skyle_clear_callbacks(client);
    }
  }
}

void FlutterSkylePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "configureTransport") {
    bool success = ConfigureTransport();
    result->Success(flutter::EncodableValue(success));
  } else {
    result->NotImplemented();
  }
}

bool FlutterSkylePlugin::ConfigureTransport() {
  skyle_client* client = flutter_skyle_get_instance();
  if (!client) {
    return false;
  }

  // Only configure transport once (shared across engines)
  if (is_transport_configured_) {
    return true;
  }

  int config_result = flutter_skyle_configure_usb_transport(
      client, kSkyleVendorId, kSkyleProductId);

  if (config_result == 0) {
    is_transport_configured_ = true;
    return true;
  }

  return false;
}

}  // namespace flutter_skyle
