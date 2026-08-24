#ifndef FLUTTER_PLUGIN_FLUTTER_SKYLE_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_SKYLE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_skyle {

class FlutterSkylePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterSkylePlugin();
  ~FlutterSkylePlugin() override;

  FlutterSkylePlugin(const FlutterSkylePlugin&) = delete;
  FlutterSkylePlugin& operator=(const FlutterSkylePlugin&) = delete;

 private:
  static void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static bool ConfigureTransport();

  static bool is_transport_configured_;
  // Live plugin-instance (engine) count: the native callback table holds one
  // subscriber per engine (multi-engine fan-out), so the destructor's
  // clear-all safety net only fires when the LAST engine goes away.
  static int instance_count_;
};

}  // namespace flutter_skyle

#endif  // FLUTTER_PLUGIN_FLUTTER_SKYLE_PLUGIN_H_
