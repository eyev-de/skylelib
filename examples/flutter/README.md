# Skyle Flutter Example (macOS · iPadOS · Android · Windows)

A Flutter app that consumes the **skylelib** C library through the **`flutter_eap`**
FFI plugin. It mirrors the Avalonia and SwiftUI examples: a segmented control
toggling a **Positioning** view and a **Video** view, a **connection indicator**,
and a live **gaze readout**.

Like the other examples, it links the **prebuilt** skylelib binaries from the
release pipeline — it does **not** compile skylelib from source.

## Layout

```
examples/flutter/
  flutter_eap/     # the vendored FFI plugin (Dart bindings + native bridge)
  app/             # the example app (this is what you run)
```

- `flutter_eap` is the binding: Dart FFI + a small C bridge, exposing the C
  callbacks as Riverpod streams. Its per-platform build files link the prebuilt
  skylelib (see "How native libs are pulled" below).
- `app` depends on `flutter_eap` via a path dependency and implements the UI.

## Prerequisites

- Flutter 3.27+ (`flutter --version`).
- The prebuilt skylelib artifacts for the platform you're building (below).
- macOS/iOS: Xcode + CocoaPods. Android: NDK r28+. Windows: Visual Studio + CMake.

## 1. Get the native artifacts

**You can skip this step entirely:** if no local SDK is found, each platform's
build **downloads the GitHub release matching the plugin's version
automatically** and caches it under `flutter_eap/.skylelib/<version>/`. The
resolution order everywhere is: `SKYLELIB_DIST` override → the repo's `dist/` →
auto-download.

To provide the artifacts yourself instead, grab the asset from the
[Releases](https://github.com/eyev-de/skylelib/releases) and unzip into `dist/`:

| Platform | Release asset | Unzip to | What the build uses |
|----------|---------------|----------|---------------------|
| macOS | `skylelib-<ver>-xcframework.zip` | `dist/skylelib.xcframework` | macOS slice: `libskylelib.a` + headers |
| iPadOS | `skylelib-<ver>-xcframework.zip` | `dist/skylelib.xcframework` | iOS device / simulator slices |
| Android | `skylelib-<ver>-android.zip` | `dist/android` | `jniLibs/<abi>/libskylelib.so` + `include` |
| Windows | `skylelib-<ver>-win-x64.zip` | `dist/win-x64` | `lib/skylelib.lib` + `bin/skylelib.dll` + `include` |

Or **build from source** (requires the skylelib source tree):

```bash
./scripts/build_sdk.sh xcframework   # macOS + iOS  -> dist/skylelib.xcframework
./scripts/build_sdk.sh android       # Android      -> dist/android
# Windows: powershell -File scripts/build_sdk.ps1 win-x64   -> dist/win-x64
```

## 2. Run

```bash
cd examples/flutter/app
flutter pub get
flutter run -d macos          # verified
# flutter run -d <ios-device>   (iPad; see notes)
# flutter run -d <android>
# flutter run -d windows
```

> **Verified:** the **macOS** target builds and runs here end to end. iPadOS,
> Android and Windows are wired to the **same** prebuilt pattern but were not
> built in this environment — build them on their respective toolchains.

With a Skyle attached, the badge turns green ("Streaming") and the views come
alive. With no device the window still launches and the badge stays gray — the
FFI + UI wiring is exercised without hardware.

## How native libs are pulled

Every platform of `flutter_eap` resolves the **prebuilt** skylelib in the same
order (first hit wins):

1. **Explicit override** — `SKYLELIB_DIST` env var (Apple pods, Android), a
   `-PSKYLELIB_DIST` gradle property (Android), or `-DSKYLELIB_DIST` (CMake).
2. **The skylelib repo's `dist/`** — source-tree development (`build_sdk.sh`).
3. **Auto-download** — fetch the [GitHub release](https://github.com/eyev-de/skylelib/releases)
   asset matching the plugin's pubspec version into
   `flutter_eap/.skylelib/<version>/`. This is the path taken when the plugin
   is consumed as a pub **git dependency** (see below).

Where each platform links it:

- **macOS / iOS** — `macos|ios/flutter_eap.podspec` (shared logic in
  `darwin/skylelib_prebuilt.rb`) point `HEADER_SEARCH_PATHS` and `OTHER_LDFLAGS`
  at the matching slice of `skylelib.xcframework` (per-SDK for iOS). Only the
  shared Apple bridge is compiled; skylelib comes from the slice's `libskylelib.a`.
- **Android** — `android/build.gradle` resolves/downloads the SDK, adds its
  `jniLibs` to `jniLibs.srcDirs` (so the `.so` is packaged into the APK), and
  passes `-DSKYLELIB_DIST` to `android/CMakeLists.txt`.
- **Windows** — `windows/CMakeLists.txt` resolves/downloads the SDK
  (win-x64 or win-arm64 by generator platform), links `lib/skylelib.lib`, and
  bundles `bin/skylelib.dll` next to the app exe.

## Using `flutter_eap` in your own app (pub git dependency)

The plugin is consumable straight from this public repo — no source checkout of
skylelib needed; the native builds download the matching prebuilt SDK:

```yaml
dependencies:
  flutter_eap:
    git:
      url: https://github.com/eyev-de/skylelib.git
      path: examples/flutter/flutter_eap
      ref: v0.1.1   # pin a release tag; the plugin downloads the same version's binaries
```

The first build per platform needs network access to fetch the release asset
(cached afterwards). To build fully offline, unzip the release yourself and set
`SKYLELIB_DIST` (Apple) / `-PSKYLELIB_DIST` (Android) / `-DSKYLELIB_DIST`
(Windows).

## How it works

- The plugin exposes the C client as Riverpod providers. The app wraps itself in
  a `ProviderScope` and watches:
  - `eapConnectionStateStreamProvider` → connection badge
  - `eapPositioningDataStreamProvider` → `PositioningView` (CustomPainter)
  - `eapVideoDataStreamProvider` → `VideoView` (decoded to a `ui.Image`)
  - `eapGazeDataStreamProvider` → gaze readout
- On `LINK_SYNCED` it enables the streams it needs (`enableGaze/Positioning/Video`),
  re-applying when the tab changes — gaze stays live in both tabs.
- Coordinates: gaze is screen-space pixels (`gaze.combined.smoothed`); positioning
  eye features are sensor-space, drawn scaled by 2464 × 2064. See
  [ARCHITECTURE.md](../avalonia/ARCHITECTURE.md) for the shared data model.

## Notes & gotchas

- **macOS App Sandbox + USB.** Flutter's macOS template enables the App Sandbox,
  which hides USB devices from the app — `connect()` then fails with `-1`
  (NOT_FOUND) even with the Skyle plugged in. This example adds
  `com.apple.security.device.usb` to `macos/Runner/DebugProfile.entitlements` and
  `Release.entitlements`; that entitlement is required for IOKit USB access.
- **Auto-connect retry.** On macOS the plugin wires its IOKit transport
  asynchronously at startup, so the first `connect()` can land before the
  transport is set. `_HomePageState._connect()` retries briefly to cover that.
- **iPadOS** needs the MFi protocol `de.eyev.eap` in `Info.plist`
  (`UISupportedExternalAccessoryProtocols`) and a real MFi-provisioned device —
  the simulator can't surface accessories.
- **Android** needs the USB-host permission entries in the app manifest (see the
  plugin README).
- The plugin's bundled generated files (`*_bindings_generated.dart`,
  `eap_providers.g.dart`) are committed, so no `build_runner` step is needed.
