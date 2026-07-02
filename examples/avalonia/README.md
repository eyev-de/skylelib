# Skyle Avalonia Example

A cross-platform .NET GUI example that consumes the prebuilt **skylelib** shared
library via P/Invoke. It demonstrates the full FFI path: lifecycle, the built-in
USB transport, and live gaze / positioning / video streams.

![overview](docs-placeholder)

## Features

- **Segmented control** to toggle between a **Positioning** view and a **Video** view.
- **Connection indicator** (gray = disconnected, amber = connecting, green = streaming).
- **Live gaze readout** showing the current smoothed gaze location in screen pixels.
- **Diagnostic positioning view** drawing per-eye boxes, pupils (with fitted
  ellipse), glints, iris rings and per-eye distance — in the camera sensor space
  (2464 × 2064), the same geometry the Flutter app uses.
- **Video view** that converts grayscale / RGB / RGBA frames to a BGRA bitmap.

No USB code lives in C#: the library's built-in transports do all USB I/O
(`eap_transport_iokit_*` on macOS, `eap_transport_usb_*` on Windows).

## Prerequisites

- .NET SDK 8.0 or newer (`dotnet --version`).
- The skylelib native shared library, built for your platform.

## 1. Get the native library

**Option A — download a release (recommended):** grab the asset for your
platform from the [Releases](https://github.com/eyev-de/skylelib/releases) (`-macos`, `-win-x64` / `-win-arm64`,
or `-linux-x86_64` / `-linux-aarch64`) and unzip it somewhere, e.g. `./sdk`.

**Option B — build from source** (requires the private skylelib source tree):

```bash
# macOS / Linux
cmake --preset make-debug && cmake --build --preset make-debug
# -> build/make-debug/lib/libskylelib.dylib (or .so)
```
```powershell
# Windows
cmake --preset default-debug && cmake --build --preset default-debug
# -> build\default-debug\lib\skylelib.dll
```

## 2. Run the example

Point `SkylelibBuildDir` at the unzipped SDK folder (Option A) or the local build
output (Option B). The build copies the native library next to the executable
automatically — it searches both `lib/` and `bin/`, so the unzipped SDK **root**
works on every OS:

```bash
# Option A: a downloaded release
dotnet run --project examples/avalonia -p:SkylelibBuildDir=/path/to/sdk

# Option B: a local source build
dotnet run --project examples/avalonia            # uses build/make-debug/lib by default
```

> On Windows the runtime DLL lives in `bin/` inside the release zip; pointing
> `SkylelibBuildDir` at the unzipped SDK root still resolves it.

With a Skyle plugged in, the badge turns green and the views come alive. With no
device connected the window still launches and the badge stays gray — useful for
validating the FFI + UI wiring without hardware.

## How it maps to the C API

| Concern | Code |
|---------|------|
| P/Invoke declarations + library resolver | `Interop/NativeMethods.cs` |
| Blittable struct mirrors (gaze, positioning, video, version, config) | `Interop/NativeStructs.cs` |
| Managed lifecycle, transport wiring, callback marshalling | `Interop/SkyleClient.cs` |
| Connection state, gaze text, stream toggling, UI pump | `ViewModels/MainViewModel.cs` |
| Window layout + segmented control | `Views/MainWindow.axaml` |
| Positioning drawing | `Views/PositioningView.cs` |
| Video drawing | `Views/VideoView.cs` |

## FFI gotchas worth knowing

- **Callbacks run on the library's background I/O thread.** Never touch Avalonia
  from them. `SkyleClient` only decodes and stores; a 60 fps `DispatcherTimer` in
  the view-model pumps the latest data onto the UI thread.
- **Keep the callback delegates rooted.** They are stored in fields on
  `SkyleClient` so the GC cannot collect them while native code holds their
  function pointers.
- **Video `pixel_data` is transient** — it is copied inside the callback because
  the pointer is only valid for the duration of the call.
- **`bool` is one byte** in C; every mirrored bool uses `[MarshalAs(U1)]`.
- A startup `Marshal.SizeOf` check guards the struct layouts against drift
  (e.g. the positioning face must be 384 bytes).
