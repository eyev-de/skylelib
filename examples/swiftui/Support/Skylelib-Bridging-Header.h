//
//  Skylelib-Bridging-Header.h
//
//  Exposes the skylelib C API to Swift. Both app targets set this as their
//  SWIFT_OBJC_BRIDGING_HEADER, so all `eap_*` functions, structs and enums are
//  visible from Swift with no module map required.
//
//  The headers are resolved via HEADER_SEARCH_PATHS (the repo `include` folder);
//  the symbols come from the linked skylelib.xcframework.
//

#import <skylelib/eap_client.h>

// macOS-only built-in IOKit USB transport. On iOS the body of this header is
// compiled away (#if TARGET_OS_OSX), so it is safe to import everywhere.
#import <skylelib/eap_transport_iokit.h>
