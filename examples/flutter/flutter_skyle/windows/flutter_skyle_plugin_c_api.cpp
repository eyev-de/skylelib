#include "include/flutter_skyle/flutter_skyle_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_skyle_plugin.h"

void FlutterSkylePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_skyle::FlutterSkylePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
