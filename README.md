# skylelib — examples & prebuilt binaries

**skylelib** is eyeV's cross-platform C library for talking to the **Skyle**
eye-tracker over USB. The library
itself is closed-source; this repository ships **runnable examples** plus the
**prebuilt binaries** for every supported platform as
[GitHub Releases](https://github.com/eyev-de/skylelib/releases).

- **Avalonia** (`examples/avalonia`) — a .NET 8 desktop GUI (macOS / Windows /
  Linux) using P/Invoke.
- **SwiftUI** (`examples/swiftui`) — a macOS + iPadOS app using a bridging
  header and the `skylelib.xcframework`.
- **Flutter** (`examples/flutter`) — a macOS / iPadOS / Android / Windows app
  using the `flutter_eap` FFI plugin.

Both show the same thing: connect to a Skyle, then stream live gaze,
positioning and video.

## 1. Get a binary

Open the [latest release](https://github.com/eyev-de/skylelib/releases/latest)
and download the asset for your platform from the table below. Every `.zip` is self-contained — it bundles
the native library **and** the public headers (`include/skylelib/…`).

| Platform | Min OS | Arch | Release asset | Contains | Linkage |
|----------|--------|------|---------------|----------|---------|
| Windows | 10 | x64 | `skylelib-<version>-win-x64.zip` | `bin/skylelib.dll`, `lib/skylelib.lib`, `include/` | dynamic |
| Windows | 10 | arm64 | `skylelib-<version>-win-arm64.zip` | `bin/skylelib.dll`, `lib/skylelib.lib`, `include/` | dynamic |
| macOS | 11 | universal (arm64 + x86_64) | `skylelib-<version>-macos.zip` | `lib/libskylelib.dylib`, `include/` | dynamic |
| Linux | glibc | x86_64 | `skylelib-<version>-linux-x86_64.zip` | `lib/libskylelib.so`, `include/` | dynamic |
| Linux | glibc | aarch64 | `skylelib-<version>-linux-aarch64.zip` | `lib/libskylelib.so`, `include/` | dynamic |
| Android | API 24 | arm64-v8a, armeabi-v7a, x86_64 | `skylelib-<version>-android.zip` | `jniLibs/<abi>/libskylelib.so`, `include/` | dynamic |
| iOS | 13 | arm64 (device) | `skylelib-<version>-ios.zip` | `lib/libskylelib.a`, `include/` | static |
| iOS Simulator | 13 | arm64 + x86_64 | `skylelib-<version>-ios-sim.zip` | `lib/libskylelib.a`, `include/` | static |
| **Apple (all)** | macOS 11 / iOS 13 | universal | `skylelib-<version>-xcframework.zip` | `skylelib.xcframework` (headers embedded) | static |

> The library is **big-endian on the wire** and exposes an opaque `eap_client`
> handle — see the headers in any release zip for the full C API.

Which example needs which asset:

| Example | Asset(s) |
|---------|----------|
| Avalonia (macOS) | `skylelib-<version>-macos.zip` |
| Avalonia (Windows) | `skylelib-<version>-win-x64.zip` or `-win-arm64.zip` |
| Avalonia (Linux) | `skylelib-<version>-linux-x86_64.zip` or `-linux-aarch64.zip` |
| SwiftUI (macOS + iPadOS) | `skylelib-<version>-xcframework.zip` |
| Flutter (macOS / iPadOS) | `skylelib-<version>-xcframework.zip` |
| Flutter (Android) | `skylelib-<version>-android.zip` |
| Flutter (Windows) | `skylelib-<version>-win-x64.zip` |

## 2. Run the Avalonia example (macOS / Windows / Linux)

Prerequisites: the [.NET 8 SDK](https://dotnet.microsoft.com/download).

```bash
# Unzip the release for your platform somewhere, e.g. ./sdk
unzip skylelib-<version>-macos.zip -d sdk

# Point the example at the unzipped SDK folder; the build copies the native
# library next to the app automatically (it searches both lib/ and bin/).
dotnet run --project examples/avalonia -p:SkylelibBuildDir=$PWD/sdk
```

On Windows the runtime DLL lives in `bin/`; pointing `SkylelibBuildDir` at the
unzipped SDK root still resolves it.

With a Skyle connected the badge turns green and the positioning / video views
come alive. With no device the window still launches (badge stays gray) — handy
for checking the FFI + UI wiring without hardware. See
[examples/avalonia/README.md](examples/avalonia/README.md) for details.

## 3. Run the SwiftUI example (macOS + iPadOS)

Prerequisites: Xcode 15+, and [XcodeGen](https://github.com/yonyz/XcodeGen)
(`brew install xcodegen`).

```bash
# Unzip the Apple xcframework to dist/ at the repo root
unzip skylelib-<version>-xcframework.zip -d dist     # -> dist/skylelib.xcframework

cd examples/swiftui
xcodegen generate            # project.yml -> SkyleSwiftUIExample.xcodeproj
open SkyleSwiftUIExample.xcodeproj
```

Pick the `SkyleSwiftUI-macOS` scheme (or `SkyleSwiftUI-iOS` for an iPad — needs a
signing team and an MFi-provisioned device). See
[examples/swiftui/README.md](examples/swiftui/README.md) for details.

## 4. Run the Flutter example (macOS / iPadOS / Android / Windows)

Prerequisites: Flutter 3.27+ and the toolchain for your target (Xcode +
CocoaPods for Apple, NDK r28+ for Android, Visual Studio + CMake for Windows).

```bash
cd examples/flutter/app
flutter pub get
flutter run -d macos          # verified; also -d <ios-device> / <android> / windows
```

No manual download needed: the `flutter_eap` plugin **fetches the prebuilt
skylelib release matching its version automatically** (cached under
`flutter_eap/.skylelib/`). To provide it yourself, unzip a release and set
`SKYLELIB_DIST` (Apple pods) / `-PSKYLELIB_DIST` (Android) / `-DSKYLELIB_DIST`
(Windows CMake). With a Skyle attached the badge turns green and the
positioning / video views come alive; with no device the app still launches
(badge stays gray). See
[examples/flutter/README.md](examples/flutter/README.md) for details.

### Use `flutter_eap` in your own Flutter app

```yaml
dependencies:
  flutter_eap:
    git:
      url: https://github.com/eyev-de/skylelib.git
      path: examples/flutter/flutter_eap
      ref: v0.1.1   # pin a release tag; binaries of the same version are fetched automatically
```

## Notes

- **Callbacks run on the library's background I/O thread.** Both examples decode
  on that thread and marshal to the UI thread before drawing — mirror that in
  your own integration.
- **Versioning:** the SDK uses plain SemVer; the version is the release tag
  (`vX.Y.Z`) and is also queryable at runtime via `skylelib_version()`.
- Questions / device access: **support@eyev.de**.
