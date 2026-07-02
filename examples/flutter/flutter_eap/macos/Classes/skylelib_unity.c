/*
 * macOS unity build.
 *
 * skylelib itself is linked as a PREBUILT static library — see flutter_eap.podspec,
 * which points HEADER_SEARCH_PATHS / OTHER_LDFLAGS at the macOS slice of
 * skylelib.xcframework (the same artifact the SwiftUI example consumes). The
 * IOKit transport and all EAP sources come from that prebuilt library.
 *
 * Only the shared Apple FFI bridge is compiled here. CocoaPods cannot compile
 * sources that live outside the pod directory (the bridge is shared with iOS in
 * ../../darwin/Classes), so we pull it in with a single #include.
 */

#include "../../darwin/Classes/flutter_eap_bridge_apple.c"
