/*
 * iOS unity build.
 *
 * skylelib itself is linked as a PREBUILT static library (skylelib.xcframework):
 * CocoaPods vendors it via flutter_eap.podspec (per-SDK header search paths for
 * the device / simulator slices), Swift Package Manager via the "skylelib"
 * binary target in ../../../Package.swift (which picks the slice itself).
 *
 * Only the shared FFI sources are compiled here: the Apple bridge and the
 * Skyle Link glue. The multi-engine callback fan-out is deliberately left out -
 * iOS is single-slot push mode. Neither CocoaPods nor SPM can compile sources
 * that live outside the pod/package directory (they are shared with the other
 * platforms), so we pull them in with #includes. On iOS the bridge's IOKit path
 * is compiled away (TARGET_OS_OSX) - transport is push-mode over
 * ExternalAccessory (see FlutterEapPlugin.swift / OutputStreamManager.swift).
 */

#include "../../../../darwin/Classes/flutter_eap_bridge_apple.c"
#include "../../../../native/link/flutter_eap_link_glue.c"
