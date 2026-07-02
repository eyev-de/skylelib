#ifndef FLUTTER_PLUGIN_FLUTTER_EAP_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_EAP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_eap {

class FlutterEapPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterEapPlugin();
  ~FlutterEapPlugin() override;

  FlutterEapPlugin(const FlutterEapPlugin&) = delete;
  FlutterEapPlugin& operator=(const FlutterEapPlugin&) = delete;

 private:
  static void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static bool ConfigureTransport();

  static bool is_transport_configured_;
};

}  // namespace flutter_eap

#endif  // FLUTTER_PLUGIN_FLUTTER_EAP_PLUGIN_H_
