/*
 * macOS unity build.
 *
 * skylelib itself is linked as a PREBUILT static library (skylelib.xcframework):
 * CocoaPods vendors it via flutter_eap.podspec, Swift Package Manager via the
 * "skylelib" binary target in ../../../Package.swift. The IOKit transport and
 * all EAP sources come from that prebuilt library.
 *
 * Only the shared FFI sources are compiled here: the Apple bridge, the
 * multi-engine callback fan-out (pull-mode platforms - iOS deliberately does
 * NOT include it), and the Skyle Link glue. Neither CocoaPods nor SPM can
 * compile sources that live outside the pod/package directory (they are
 * shared with the other platforms), so we pull them in with #includes.
 */

#include "../../../../darwin/Classes/flutter_eap_bridge_apple.c"
#include "../../../../native/fanout/flutter_eap_fanout.c"
#include "../../../../native/link/flutter_eap_link_glue.c"
