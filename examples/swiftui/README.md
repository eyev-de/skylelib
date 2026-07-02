# Skyle SwiftUI Example (macOS + iPadOS)

A SwiftUI app that consumes the **skylelib** C library and runs on both **macOS**
and **iPadOS** from one shared codebase. It mirrors the Avalonia example: a
segmented control toggling a **Positioning** view and a **Video** view, a
**connection indicator**, and a live **gaze readout**.

The only platform-specific part is the transport:

| Platform | Transport | How |
|----------|-----------|-----|
| **macOS** | built-in IOKit | `eap_transport_iokit_*` (no USB code in Swift) |
| **iPadOS** | ExternalAccessory + push mode | `eap_client_set_push_transport` + `eap_client_process_received_data` + `eap_client_tick` over an `EASession` |

The C API is exposed to Swift through a **bridging header**
(`Support/Skylelib-Bridging-Header.h`) — no module map required. Symbols come from
the prebuilt `skylelib.xcframework`.

## Prerequisites

- Xcode 15+ (uses the iOS / macOS SDKs).
- [XcodeGen](https://github.com/yonyz/XcodeGen) — `brew install xcodegen`.
- The Apple `skylelib.xcframework`.

## 1. Get the xcframework

The project expects `dist/skylelib.xcframework` at the repo root.

**Option A — download a release (recommended):** grab
`skylelib-<version>-xcframework.zip` from the [Releases](https://github.com/eyev-de/skylelib/releases) and
unzip it into `dist/`:

```bash
unzip skylelib-<version>-xcframework.zip -d dist   # -> dist/skylelib.xcframework
```

**Option B — build from source** (requires the private skylelib source tree):

```bash
./scripts/build_sdk.sh xcframework
# -> dist/skylelib.xcframework  (macOS + iOS device + iOS simulator, static slices)
```

(The macOS slice contains the IOKit transport; the iOS slices compile that away
and rely on the push API.)

## 2. Generate the Xcode project

```bash
cd examples/swiftui
xcodegen generate          # reads project.yml -> SkyleSwiftUIExample.xcodeproj
open SkyleSwiftUIExample.xcodeproj
```

## 3. Build & run

**macOS** — pick the `SkyleSwiftUI-macOS` scheme and run, or:

```bash
xcodebuild -scheme SkyleSwiftUI-macOS -destination 'platform=macOS' build
```

**iPadOS** — pick `SkyleSwiftUI-iOS`. The simulator can't talk to a real
accessory, so for live data run on a physical iPad:

1. Select your iPad as the run destination.
2. Set a development team (Signing & Capabilities) — the generated target has
   signing left blank.
3. The Info.plist already declares the MFi protocol
   (`UISupportedExternalAccessoryProtocols = ["de.eyev.eap"]`).

> The Skyle must be MFi-provisioned for the `de.eyev.eap` protocol for
> ExternalAccessory to surface it. Without that, `EAAccessoryManager` won't list it.

## Project layout

```
examples/swiftui/
  project.yml                         # XcodeGen spec (both targets)
  Support/
    Skylelib-Bridging-Header.h        # imports <skylelib/...> into Swift
  Sources/
    App.swift                         # @main App
    SkyleClient.swift                 # FFI lifecycle, callbacks, macOS transport
    ExternalAccessoryTransport.swift  # iPadOS push transport (EASession)
    SkyleViewModel.swift              # ObservableObject; marshals to main thread
    Model.swift                       # ViewMode, CGImage builder, helpers
    Views/
      ContentView.swift               # badge + segmented control + gaze readout
      PositioningCanvasView.swift     # Canvas: eye boxes, pupils, glints, iris
      VideoCanvasView.swift           # Image(decorative:) from the frame
```

## How it works

- **`SkyleClient`** wraps `eap_client`. It does the two-phase init
  (`get_instance` → `set_transport` → `set_callbacks` → `connect`), registers C
  callbacks as non-capturing `@convention(c)` closures, and routes them back to
  the instance via an `Unmanaged` context pointer passed as the callback
  `user_data`.
- **Callbacks run on the library's background I/O thread.** `SkyleClient` only
  decodes; `SkyleViewModel` hops to the main thread (`DispatchQueue.main.async`)
  before touching `@Published` state.
- **Streams** are enabled only after `EAP_STATE_LINK_SYNCED`, and re-applied when
  the tab changes (`applyStreams()`): gaze always on, positioning/video per tab.
- **Coordinates:** gaze is screen-space pixels (`both.smoothed`); positioning eye
  features are sensor-space, drawn scaled by 2464 × 2064. See
  [ARCHITECTURE.md](../avalonia/ARCHITECTURE.md) in the Avalonia example for the
  full data-model and coordinate notes shared by every binding.

## Notes & gotchas

- The C structs import directly into Swift; callback payloads arrive as typed
  `UnsafePointer<eap_*_response>` — read `.pointee` and copy what you keep.
- `eap_video_response.pixel_data` is **transient** — it is copied inside the
  callback (`memcpy` into a Swift array).
- The iOS write path uses a small backpressured queue gated on the output
  stream's `hasSpaceAvailable`, matching the proven `flutter_eap` approach.
- `HEADER_SEARCH_PATHS` points recursively into `dist/skylelib.xcframework`, so
  both the `<skylelib/...>` headers and the linked symbols come from the
  xcframework — no source tree required.
