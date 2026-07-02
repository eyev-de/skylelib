#include "include/flutter_eap/flutter_eap_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_eap_plugin.h"

void FlutterEapPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_eap::FlutterEapPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
