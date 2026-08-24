// swift-tools-version: 5.9
// Swift Package Manager manifest for the flutter_skyle iOS plugin.
// Dual support: CocoaPods consumers keep using ../flutter_skyle.podspec, which
// compiles the same sources from this package layout.

import PackageDescription
import Foundation

// skylelib is a PREBUILT static library (skylelib.xcframework). SPM has no
// install hooks (the podspec's ruby vendoring cannot run), so the manifest
// resolves it in two ways:
//  1. A local copy vendored INSIDE this package at .skylelib/skylelib.xcframework.
//     `pod install` of the iOS podspec creates it as a side effect; pure-SPM
//     developers run <plugin>/scripts/vendor_xcframework.sh (resolves
//     SKYLELIB_DIST / the repo's dist/ / the GitHub release, like the podspec).
//     Used whenever present - this is the development path.
//  2. Otherwise the versioned GitHub release asset below. The checksum MUST
//     match the UPLOADED skylelib-<version>-xcframework.zip - it is the plain
//     SHA-256 of that file. The release pipeline writes both values: the
//     Codemagic sdk-apple workflow runs scripts/sync_spm_pin.sh on the zip it
//     just built, right before it publishes the examples and uploads that same
//     zip, so the published manifest always matches its release. The script
//     rewrites BOTH platforms (one xcframework serves both), so these two
//     values always equal the ones in ../../macos/flutter_skyle/Package.swift.
//     The values checked in here are the last pin CI produced; refresh them by
//     hand only when publishing outside that pipeline, with
//     `scripts/sync_spm_pin.sh <version> <zip>` (see docs/SDK_DISTRIBUTION.md
//     section 8.1 in the skylelib repo).
// The binary target consumes the whole xcframework, so SPM picks the matching
// slice per SDK (ios-arm64 for device, ios-arm64_x86_64-simulator for the
// simulator) - no per-SDK search paths as in the podspec.
// NOTE: Xcode caches manifest evaluation. After creating or removing the local
// copy, re-resolve packages (File > Packages > Reset Package Caches, or
// `flutter clean`) for the switch to take effect.
let skylelibVersion = "2.1.0"
let skylelibChecksum = "6d5327ce312309b04cca05564b62f7bcb50bb8894310be59be1995bdf3d79f6e"

let localXCFrameworkPath = ".skylelib/skylelib.xcframework"
let hasLocalXCFramework = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + localXCFrameworkPath)

let skylelibTarget: Target = hasLocalXCFramework
    ? .binaryTarget(
        name: "skylelib",
        path: localXCFrameworkPath)
    : .binaryTarget(
        name: "skylelib",
        url: "https://github.com/eyev-de/skylelib/releases/download/v\(skylelibVersion)/skylelib-\(skylelibVersion)-xcframework.zip",
        checksum: skylelibChecksum)

let package = Package(
    name: "flutter_skyle",
    platforms: [
        // The floor of the prebuilt iOS slices (build_sdk.sh builds them with
        // IOS_DEPLOYMENT_TARGET=13.0), which is also Flutter's iOS minimum.
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-skyle", targets: ["flutter_skyle"])
    ],
    dependencies: [],
    targets: [
        // Swift plugin class (FlutterSkylePlugin) plus the ExternalAccessory
        // push-mode transport (EASession streams). The C bridge is a separate
        // target because SPM does not allow mixed Swift/C targets.
        .target(
            name: "flutter_skyle",
            dependencies: [
                "flutter_skyle_bridge"
            ],
            linkerSettings: [
                .linkedFramework("ExternalAccessory")
            ]
        ),
        // C FFI bridge: a unity file that includes the shared Apple bridge
        // (../../darwin/Classes) and the Skyle Link glue (../../native/link).
        // The multi-engine fan-out is deliberately NOT compiled here - iOS is
        // single-slot push mode. The public header
        // (include/flutter_skyle_ios.h) exposes only the functions
        // FlutterSkylePlugin.swift needs. skylelib's namespaced headers
        // (<skylelib/...>) come from the binary target's Headers dir.
        .target(
            name: "flutter_skyle_bridge",
            dependencies: [
                "skylelib"
            ]
        ),
        skylelibTarget,
    ],
    cLanguageStandard: .c17
)
