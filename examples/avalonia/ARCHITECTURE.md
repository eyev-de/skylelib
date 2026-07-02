# Skyle Example — Architecture & Porting Guide

This document describes **what the Avalonia example looks like and how it works**, and
is written so you can reproduce it in another UI stack (e.g. **Flutter** or **SwiftUI**).
Read it as the *spec* for "a minimal Skyle viewer app"; the Avalonia code is one
reference implementation of that spec.

The example is deliberately small: connect to the eye tracker, show whether it's
connected, and visualise three live data streams (gaze, positioning, video). Everything
else (calibration, file upload, control settings) is intentionally left out.

---

## 1. What the app looks like

```
┌──────────────────────────────────────────────────────────┐
│ ● Streaming                          Skyle · FW 1.x · SN … │   ← connection badge + device info
├──────────────────────────────────────────────────────────┤
│              ┌───────────────┬───────────────┐            │   ← segmented control
│              │  Positioning  │     Video     │            │     (mutually exclusive)
│              └───────────────┴───────────────┘            │
├──────────────────────────────────────────────────────────┤
│                                                            │
│        ┌──────────────────────────────────────┐           │
│        │  ▢ eye box      ▢ eye box             │           │   ← content area:
│        │   ◯ iris ring    ◯ iris ring          │           │     Positioning OR Video
│        │   ◉ pupil+ellipse ◉ pupil+ellipse     │           │     (whichever tab is active)
│        │   · ·  glints     · ·  glints         │           │
│        │  Distance  L 580 mm   R 585 mm        │           │
│        └──────────────────────────────────────┘           │
│                                                            │
├──────────────────────────────────────────────────────────┤
│  Gaze: (1024, 768) px · Fixation                           │   ← live gaze readout
└──────────────────────────────────────────────────────────┘
```

Three required features:

1. **Connection indicator** — a colored dot + label: gray = disconnected, amber =
   connecting/handshaking, green = streaming, red = error.
2. **Segmented control** — toggles between the **Positioning** view and the **Video**
   view. Only the active stream is requested from the device (bandwidth saving); gaze
   stays on in both so the readout is always live.
3. **Gaze readout** — the current smoothed gaze point in screen pixels + the movement
   classification (fixation / saccade).

The **Positioning** view is a *diagnostic* drawing: per-eye bounding box, pupil (with its
fitted ellipse), the two glints, the iris ring, and per-eye distance. The **Video** view
shows the device camera feed.

---

## 2. Architecture at a glance

```
            ┌─────────────────────────────────────────────────┐
  UI layer  │  Views (segmented control, positioning canvas,  │   platform-specific
            │         video bitmap, badge, gaze text)          │   (Avalonia / Flutter / SwiftUI)
            └───────────────▲───────────────┬─────────────────┘
                            │ observable     │ user toggles tab
                            │ state          ▼
            ┌─────────────────────────────────────────────────┐
  App glue  │  ViewModel / Controller                         │   platform-idiomatic
            │  - holds latest snapshots                        │   (MVVM, ChangeNotifier,
            │  - maps connection state → label/color           │    ObservableObject…)
            │  - throttles device rate → UI rate (~60 fps)     │
            └───────────────▲───────────────┬─────────────────┘
                            │ events         │ enable/disable streams
                            │ (bg thread)    ▼
            ┌─────────────────────────────────────────────────┐
  Binding   │  SkyleClient (thin FFI wrapper)                  │   per-language FFI
            │  - lifecycle, transport wiring                   │
            │  - decode callback structs → managed objects     │
            │  - raise events; copy transient buffers          │
            └───────────────▲───────────────┬─────────────────┘
                            │ C callbacks    │ C calls
                            │ (I/O thread)   ▼
            ┌─────────────────────────────────────────────────┐
  Native    │  libskylelib  (eap_client + built-in transport)  │   shipped, unchanged
            │  background I/O thread: USB ↔ iAP2 ↔ EAP parsing  │
            └─────────────────────────────────────────────────┘
```

The native library does all the hard work (USB, the iAP2 handshake, EAP message parsing,
heartbeat, reconnect) on its **own background thread**. A binding's only jobs are:
**(a)** wire up a transport, **(b)** register callbacks, **(c)** marshal the decoded data
to the UI thread.

In the Avalonia code these three layers are:

| Layer | Files |
|-------|-------|
| Binding | `Interop/NativeMethods.cs`, `Interop/NativeStructs.cs`, `Interop/NativeEnums.cs`, `Interop/SkyleClient.cs` |
| App glue | `ViewModels/MainViewModel.cs`, `ViewModels/ViewModelBase.cs` |
| UI | `Views/MainWindow.axaml`, `Views/PositioningView.cs`, `Views/VideoView.cs` |

---

## 3. The native API contract (replicate this in any binding)

All of the following lives in `include/skylelib/eap_client.h` and the per-message headers
under `include/skylelib/eap/`. The library is C with `extern "C"` linkage and an opaque
`eap_client*` handle.

### 3a. Lifecycle / init sequence

This exact order is what `SkyleClient.Start()` does:

```
client = eap_client_get_instance();          // singleton, one per process
                                             // PHASE 1 — transport (starts the I/O thread)
transport = eap_transport_<platform>_create(&cfg);   // see 3b
eap_client_set_transport(client, &transport_config); // write/read/check fn-ptrs + handle
                                             // PHASE 2 — callbacks
eap_client_set_callbacks(client, &callback_config);  // on_gaze, on_positioning, …
eap_client_connect(client);                  // begin iAP2 handshake
```

Teardown (on app close): `eap_client_disconnect` → `eap_client_stop_background` (joins the
I/O thread) → `eap_transport_<platform>_destroy`. Only after the thread is stopped is it
safe to release the callback closures.

### 3b. Transport — pick per platform

The library ships **built-in USB transports** for desktop, so you don't implement USB I/O:

| Platform | Transport | Create | Write / Read fn-ptr | Device-present check |
|----------|-----------|--------|---------------------|----------------------|
| macOS | IOKit | `eap_transport_iokit_create(&cfg)` | `eap_transport_iokit_write` / `_read` (symbols) | `eap_transport_iokit_get_check_callback()` |
| Windows | WinUSB | `eap_transport_usb_create(&cfg)` | `eap_transport_usb_write` / `_read` (symbols) | `eap_transport_usb_get_check_callback()` |
| iOS | **push mode** | — (ExternalAccessory) | you call `eap_client_process_received_data()` | optional |
| Android | callback transport | your JNI write/read over USB Host API | your `bool(*)(void*)` |

`cfg` is `{ vendor_id = 0x3729, product_id = 0x7333, timeout_ms, verbose }`.

The desktop pattern: get the **native** write/read function-pointers by symbol lookup
(`NativeLibrary.GetExport` in C#, `dlsym`/direct reference in Swift, `lookup` in Dart),
put them into `eap_transport_config` together with the transport handle as
`transport_user_data`, and call `eap_client_set_transport`. No managed code sits on the
USB hot path.

**iOS** has no built-in transport — use the push API instead:
`eap_client_set_push_transport(write_fn, check_fn, ctx)`, feed received bytes with
`eap_client_process_received_data(data, len)`, and call `eap_client_tick()` ~every 200 ms
for heartbeat/timeout/reconnect.

### 3c. Callbacks & threading (the #1 thing to get right)

You register C function pointers in `eap_callback_config`. The example uses five:

| Field | Fires with | Used for |
|-------|-----------|----------|
| `on_state_change` | `(old_state, new_state)` enums | connection badge; trigger stream-enable on `LINK_SYNCED` |
| `on_gaze` | `const eap_gaze_response*` | gaze readout |
| `on_positioning` | `const eap_positioning_response*` | positioning view |
| `on_video` | `const eap_video_response*` | video view |
| `on_version` | `const eap_version_response*` | device info (heartbeat, ~2 Hz) |

**Every callback runs on the library's background I/O thread.** Rules every binding must
follow:

1. **Never touch the UI** from inside a callback. Decode + stash, then hand off to the UI
   thread (`Dispatcher.UIThread` / `setState` via the Dart isolate / `DispatchQueue.main`).
2. **Keep the callback closures alive** for the client's lifetime, or the GC/ARC frees
   memory the native side still calls. (C#: store the delegates in fields. Dart: keep the
   `NativeCallable` referenced. Swift: keep the context object referenced.)
3. **Copy transient buffers immediately.** `eap_video_response.pixel_data` is only valid
   *during* the call — copy it before returning. Struct payloads should also be copied out
   (don't retain the pointer).

The Avalonia app decouples the device rate from rendering: callbacks write into
`volatile` "latest" fields, and a 60 fps `DispatcherTimer` in the view-model pumps the
newest snapshot to the UI. Any equivalent throttle works (a Flutter `Ticker`, a SwiftUI
`TimelineView`/`CADisplayLink`); per-frame UI posts also work at these rates.

### 3d. Streaming control

After the link is up (`on_state_change` reports `EAP_STATE_LINK_SYNCED`), enable the
streams you want. They are **only valid in `LINK_SYNCED`**:

```
eap_client_enable_gaze(client, true);
eap_client_enable_positioning(client, on/off);   // on when Positioning tab active
eap_client_enable_video(client, on/off);         // on when Video tab active
```

Re-apply whenever the tab changes (and once when first synced).

---

## 4. The data you render

### Gaze (`eap_gaze_response`, gaze_messages.h)

Three `eap_complex_gaze` blocks: `left`, `right`, `both`. Use **`both.smoothed`** (a
`pointf`) for the readout — **screen pixels** in the device's configured display space.
`both.type` is the movement class (0 fixation, 1 saccade, 2 unknown). Treat `(0,0)` as
"no gaze".

> The screen-pixel scale depends on the resolution the device knows. Optionally call
> `eap_client_send_display_info()` with your real resolution/size so the numbers match
> your screen; the example omits this and shows raw values.

### Positioning (`eap_positioning_response`, positioning_messages.h)

A 384-byte `eap_complex_face`: a screen-space face `bounding_rect`, then `left`/`right`
`eap_complex_eye`. **Coordinate systems are mixed**, which is the key porting subtlety:

| Field | Type | Space |
|-------|------|-------|
| `face.bounding_rect` | `rectf` | **screen** pixels |
| `eye.bounding_rect` | `rectu` | **image/sensor** pixels |
| `eye.pupil.center` / `.ellipse` | `pointf` / `rotated_rect` | **image/sensor** pixels |
| `eye.left_glint.center` / `eye.right_glint.center` | `pointf` | **image/sensor** pixels |
| `eye.iris.center` + `.top/.left/.right/.bottom` | `pointf` | **image/sensor** pixels |
| `eye.iris.distance_mm` | `float` | millimetres |

The example draws everything in **sensor space**, letterboxed into the view with a fixed
aspect of **2464 × 2064** (the same constant the Flutter app uses in
`menu_positioning_view.dart`). Mapping is a single linear scale, no mirroring:

```
sx = ox + featureX / 2464 * drawW
sy = oy + featureY / 2064 * drawH      (drawW/drawH = the letterboxed content rect)
```

It deliberately **does not** draw the screen-space face rect (different coordinate space),
using the per-eye image-space boxes instead so one transform covers the whole drawing.
The iris ring radius is derived from the four extreme iris points; the pupil ellipse uses
`ellipse.size` + `ellipse.angle` (degrees, OpenCV convention). Skip any feature whose
center is `(0,0)`.

### Video (`eap_video_response`, video_messages.h)

`{ width, height, channels, pixel_data, pixel_data_length }`. `channels` is 1 (grayscale),
3 (RGB) or 4 (RGBA). Convert to your platform's bitmap format and draw scaled to fit
(preserve aspect). The example builds a reused BGRA bitmap:

```
ch == 1: gray → B=G=R=gray, A=255
ch == 3: RGB  → BGRA
ch == 4: RGBA → BGRA
```

Remember `pixel_data` is transient — copy in the callback (see 3c).

### Byte order & struct layout (FFI marshalling)

- **Big-endian is wire-only.** By the time a struct reaches your callback it's already in
  host byte order — no swapping needed. Map the C structs field-for-field.
- C `bool` is **1 byte** (C#: `[MarshalAs(U1)]`; Dart: `Uint8`; Swift: imported as `Bool`).
- Natural alignment matches C: e.g. the `int64 timestamp_ms` in `eap_message_header` sits
  at offset 8 (header is 24 bytes); `eap_complex_gaze` pads to 20. A cheap safety net is a
  startup assertion that `sizeof(complex_face) == 384` etc. (`SkyleClient.VerifyStructLayouts`).

---

## 5. How the Avalonia reference maps to code

| Responsibility | File | Notes for porters |
|----------------|------|-------------------|
| P/Invoke decls + library loader | `Interop/NativeMethods.cs` | resolves the lib copied next to the exe |
| C struct mirrors | `Interop/NativeStructs.cs` | `[StructLayout(Sequential)]`, `[MarshalAs(U1)] bool` |
| Enums | `Interop/NativeEnums.cs` | `eap_connection_state`, movement type |
| Lifecycle + callbacks + decode | `Interop/SkyleClient.cs` | platform transport pick, delegate rooting, buffer copy, size asserts |
| State→UI, throttle, tab logic | `ViewModels/MainViewModel.cs` | 60 fps pump, `ApplyStreams()` on sync/tab change |
| Window + segmented control | `Views/MainWindow.axaml` | two RadioButtons styled as segments |
| Positioning drawing | `Views/PositioningView.cs` | custom `Render()`, sensor-space mapping |
| Video drawing | `Views/VideoView.cs` | channel→BGRA conversion, scaled draw |
| Native lib copy | `SkyleAvaloniaExample.csproj` | `CopySkylelibNative` target |

---

## 6. Porting checklist (Avalonia → Flutter → SwiftUI)

| Concern | Avalonia (this example) | Flutter | SwiftUI |
|---------|-------------------------|---------|---------|
| FFI mechanism | `[DllImport]` + `NativeLibrary` | `dart:ffi` (or reuse the existing **`flutter_eap`** package) | direct C import (bridging header / module map) |
| Callback closures | `[UnmanagedFunctionPointer]` delegates in fields | `NativeCallable.listener` (runs on the isolate) — keep referenced | top-level `@convention(c)` fn + `Unmanaged` context ptr |
| Routing callback → instance | `user_data` unused; instance via captured `this` | `SendPort` / the listener's isolate | pass `Unmanaged.passUnretained(self).toOpaque()` as `user_data`, `takeUnretainedValue()` inside |
| Struct mapping | `[StructLayout]` structs | `ffi.Struct` subclasses (`@Array`, `@Uint8`…) | C structs import directly into Swift |
| To the UI thread | `Dispatcher.UIThread.Post` | listener already on isolate → `setState`/Stream | `DispatchQueue.main.async` |
| Throttle device→UI | `DispatcherTimer` 16 ms | `Ticker` / `StreamController` + `addPostFrameCallback` | `TimelineView(.animation)` / `CADisplayLink` |
| Connection state | bound `ConnectionLabel`/`ConnectionBrush` | `ValueNotifier`/`Provider` | `@Published` on an `ObservableObject` |
| Segmented control | styled `RadioButton`s | `CupertinoSegmentedControl` / `SegmentedButton` | `Picker(.segmented)` |
| Positioning drawing | `Control.Render(DrawingContext)` | `CustomPainter` | `Canvas { ctx, size in … }` |
| Video bitmap | `WriteableBitmap` (BGRA) | `ui.decodeImageFromPixels` (RGBA) → `RawImage` | `CGImage` from a `CGContext`/`vImage` → `Image` |
| Native artifact | dylib/dll copied next to exe | `.so`/`.framework`/`.dll` in the plugin's platform folders | `.xcframework` (see `docs/SDK_DISTRIBUTION.md`) |

> **Flutter shortcut:** a working Dart FFI binding already exists as `flutter_eap`
> (referenced in `docs/SDK_DISTRIBUTION.md` §0.5). A Flutter example should consume that
> package rather than re-implement `dart:ffi` from scratch — then this document only
> guides the *UI* half (Positioning `CustomPainter`, Video `RawImage`, segmented control,
> gaze text).

---

## 7. Platform integration notes

- **macOS** — IOKit transport, no entitlements needed for local USB. Ship/copy the
  `.dylib` (or link a `.framework`/`.xcframework`).
- **Windows** — WinUSB transport; the device needs the WinUSB driver bound to it. Ship
  `skylelib.dll`.
- **iOS** — no raw USB: use the **push API** with the ExternalAccessory framework
  (`eap_client_set_push_transport` + `process_received_data` + `tick`). Link the static
  `.xcframework`. Requires the MFi accessory protocol entries in `Info.plist`.
- **Android** — implement `transport_read`/`transport_write` in Kotlin/JNI over the USB
  Host API and pass them through `eap_transport_config`. Ship per-ABI `.so`.

See `docs/PLATFORM_INTEGRATION.md` for the full transport story and
`docs/SDK_DISTRIBUTION.md` for which artifact each platform consumes.

---

## 8. Gotchas (all learned in this example)

- Callbacks are on a **background thread** — marshal to the UI; never draw from them.
- **Root the callback closures**, or native code calls freed memory.
- **Copy `pixel_data` (and any payload) inside the callback** — the pointer is transient.
- Enable streams **only after `LINK_SYNCED`**; re-enable on reconnect.
- Positioning eye-features are **sensor-space** (scale by 2464 × 2064); gaze is
  **screen-space** pixels. Don't mix them.
- `bool` is **1 byte**; big-endian is **wire-only** (callback structs are host-order).
- The client is a **process singleton** (`eap_client_get_instance`) — one per app; tear it
  down cleanly on exit.
