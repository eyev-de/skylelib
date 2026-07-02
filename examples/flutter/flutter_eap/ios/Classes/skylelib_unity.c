/*
 * iOS unity build.
 *
 * skylelib itself is linked as a PREBUILT static library — see flutter_eap.podspec,
 * which points HEADER_SEARCH_PATHS / OTHER_LDFLAGS at the iOS device / simulator
 * slices of skylelib.xcframework (per-SDK).
 *
 * Only the shared Apple FFI bridge is compiled here. CocoaPods cannot compile
 * sources that live outside the pod directory (the bridge is shared with macOS
 * in ../../darwin/Classes), so we pull it in with a single #include. On iOS the
 * bridge's IOKit path is compiled away (TARGET_OS_OSX) — transport is push-mode
 * over ExternalAccessory (see FlutterEapPlugin.swift / OutputStreamManager.swift).
 */

#include "../../darwin/Classes/flutter_eap_bridge_apple.c"
