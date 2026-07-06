# flutter_eap — Public API Reference

**flutter_eap** is the Flutter/Dart binding for **skylelib**, eyeV's
cross-platform library for the **Skyle** eye-tracker (VID `0x3729`, PID
`0x7333`). It talks to the prebuilt native skylelib over `dart:ffi` and exposes a
high-level, stream-based Dart API plus optional Riverpod providers.

- **Package:** `flutter_eap`
- **Platforms:** Android (USB Host), iOS/iPadOS (ExternalAccessory), macOS
  (IOKit), Windows (WinUSB).
- **Native library:** fetched automatically at build time — the plugin downloads
  the matching skylelib [release](https://github.com/eyev-de/skylelib/releases)
  for its own version. See the package [README](README.md) for setup and
  [ARCHITECTURE.md](ARCHITECTURE.md) for the transport internals.

> This document covers the **public Dart API**. For the underlying C API see the
> [skylelib Documentation.md](../../Documentation.md).

---

## Table of contents

1. [Install & import](#install--import)
2. [Quick start](#quick-start)
3. [EapClient](#eapclient)
   - [Lifecycle](#lifecycle)
   - [Connection & state](#connection--state)
   - [Data streams](#data-streams)
   - [Feature commands](#feature-commands)
   - [Control settings](#control-settings)
   - [Calibration](#calibration)
   - [File upload](#file-upload)
   - [Device logging & diagnostics](#device-logging--diagnostics)
4. [Riverpod providers](#riverpod-providers)
5. [Data models](#data-models)
6. [Enumerations](#enumerations)
7. [Coordinate systems](#coordinate-systems)
8. [Threading & errors](#threading--errors)

---

## Install & import

```yaml
dependencies:
  flutter_eap:
    git:
      url: https://github.com/eyev-de/skylelib.git
      path: examples/flutter/flutter_eap
      ref: v0.2.0   # pin a release tag; the matching binaries are fetched automatically
```

The package offers three entry points so you import only what you need:

| Import | Exposes |
|--------|---------|
| `package:flutter_eap/flutter_eap.dart` | `EapClient` + all data models. The usual choice. |
| `package:flutter_eap/flutter_eap_models.dart` | Data models **only** — no client, no providers. Use in isolates / overlay windows to avoid accidental client init. |
| `package:flutter_eap/flutter_eap_providers.dart` | `EapClient` + models + the Riverpod providers. |

---

## Quick start

```dart
import 'package:flutter_eap/flutter_eap.dart';

final client = EapClient();
client.initialize();               // once, at startup

client.stateStream.listen((state) {
  if (state.isReady) {             // ConnectionState.linkSynced
    client.enableGaze(true);
  }
});

client.gazeDataStream.listen((g) {
  print('gaze: ${g.gazeX}, ${g.gazeY}');   // combined, smoothed, screen pixels
});

await client.connect();

// ... later ...
await client.disconnect();
await client.dispose();
```

---

## EapClient

`EapClient` is the single high-level facade. It implements a set of segregated
interfaces so you (or Riverpod) can depend on just one capability:

`EapGaze`, `EapPositioning`, `EapVersion`, `EapCalibration`, `EapVideo`,
`EapFileUpload`, `EapDeviceLogging`, `EapControl`.

### Lifecycle

```dart
void initialize();          // create native client + wire streams (idempotent)
Future<void> dispose();     // disconnect, cancel subscriptions, free native client
Future<void> connect();     // start handshake + background I/O (throws EapException on failure)
Future<void> disconnect();  // reset the protocol connection
```

Call `initialize()` exactly once before anything else; every other method throws
`StateError` until you do. `connect()` returns once the handshake has been
kicked off — watch `stateStream` for `ConnectionState.linkSynced` before
enabling streams.

### Connection & state

```dart
ConnectionState get state;              // current state
bool get isReady;                       // == state.isReady (linkSynced)
bool get isConnected;                   // == state.isConnected (any non-disconnected/error)
Stream<ConnectionState> get stateStream;
Stream<String> get errorStream;
```

### Data streams

All streams are broadcast and emit on the platform/UI isolate (data is marshalled
off the native I/O thread for you).

| Getter | Type | Notes |
|--------|------|-------|
| `gazeDataStream` | `Stream<GazesData>` | ~60 Hz when gaze is enabled. |
| `positioningDataStream` | `Stream<FaceData>` | ~30 Hz when positioning is enabled. |
| `videoDataStream` | `Stream<VideoFrame>` | Raw frames (dimensions + bytes) when video is enabled. |
| `controlDataStream` | `Stream<ControlData>` | Device settings; emits on every device push and after coalesced writes. |
| `calibrationStream` | `Stream<CalibrationMessage>` | Calibration workflow events (see [Calibration](#calibration)). |
| `fileStatusStream` | `Stream<FileUploadStatus>` | Raw device file-transfer status. |
| `deviceLogStream` | `Stream<EapLogMessage>` | Firmware log lines (only while device logging is on). |
| `logStream` | `Stream<EapLogMessage>` | Diagnostic logs from the Dart/FFI layer itself. |

### Feature commands

Each `enable*` is a no-op (logs a warning) unless `isReady`; the async
`Future`s complete once the request is queued and throw `EapException` on a
native error.

```dart
Future<void> enableGaze(bool enable);
Future<void> enablePositioning(bool enable);
Future<void> enableVideo(bool enable);
Future<void> enableControl(bool enable);
Future<void> enableDeviceLogging(bool enable);
Future<VersionData> requestVersion();          // resolves with device/firmware info
```

### Control settings

Device settings are exposed both as a snapshot (`controlData`) and as individual
read/write properties. **Enable the control stream first** (`enableControl(true)`)
so the device pushes its current persisted state.

```dart
ControlData get controlData;                    // last known full state

// Getters
bool get isStandbyEnabled;
bool get isAutoPauseEnabled;
bool get isPauseEnabled;
TrackingMode get trackingMode;                  // binocular / left / right
int  get gazeFilter;                            // 0–255
int  get fixationFilter;                        // 0–255
bool get isAssistiveTouchEnabled;
bool get showTrackingDetails;
bool get isHidEnabled;
bool get isEthernetEnabled;

// Setters (each sends an updated ControlMessage to the device)
set isStandbyEnabled(bool v);
set isAutoPauseEnabled(bool v);
set isPauseEnabled(bool v);
set trackingMode(TrackingMode v);
set gazeFilter(int v);
set fixationFilter(int v);
set isAssistiveTouchEnabled(bool v);
set showTrackingDetails(bool v);
set isHidEnabled(bool v);
set isEthernetEnabled(bool v);
set isAssistiveTouchAndHidEnabled(bool v);      // toggles both at once
void defaultFilter();                           // gazeFilter=5, fixationFilter=30

// Or send a whole message explicitly:
Future<void> sendControl(ControlMessage message);
```

> **Write coalescing.** Setters issued before the device has pushed its current
> state are queued as field-level deltas and folded onto the device-fresh state
> on the next ingest, then sent back as one coalesced message. This preserves
> user intent across (re)connect races without clobbering the device's persisted
> settings with defaults. Later writes to the same field supersede earlier ones.

**Display info** — tell the device your screen geometry so it can map gaze
coordinates and drive calibration:

```dart
Future<void> sendDisplayInfo(DisplayInfo info); // fire-and-forget; cached
DisplayInfo? get displayInfo;                   // most recently set value
```

The value is cached and **auto-resent every time the link becomes ready**
(connect / reconnect / hot restart), so it is safe to call before connecting.

### Calibration

```dart
Future<void> startCalibration(CalibrationConfig config);
Future<void> collectCalibrationPoints();   // signal "user is fixating this point"
Future<void> abortCalibration();
```

Drive the workflow off `calibrationStream`, whose events are subclasses of
`CalibrationMessage`:

| Event | Meaning |
|-------|---------|
| `NextCalibrationPointMessage` | Show `point` (index + screen coords), then call `collectCalibrationPoints()`. |
| `ProgressCalibrationPointMessage` | Collection progress 0–100% for the current point. |
| `PausedCalibrationMessage` | Device paused collection. |
| `AbortCalibrationMessage` | Device aborted the calibration. |
| `FinishedCalibrationMessage` | Done — carries a `CalibrationResult` with per-eye quality points. |

Typical loop:

```dart
client.calibrationStream.listen((msg) {
  switch (msg) {
    case NextCalibrationPointMessage(:final point):
      showTarget(point.coordinates);
      client.collectCalibrationPoints();
    case ProgressCalibrationPointMessage(:final progress):
      updateBar(progress.progress);
    case FinishedCalibrationMessage(:final result):
      showQuality(result);
    default:
      break;
  }
});

await client.startCalibration(CalibrationConfig(
  points: CalibrationType.five.array,   // [0,2,6,8,4]
  coordinates: const [],                // empty = device chooses positions
  resolution: const Sizeu(1920, 1080),
  size: const Size2d(340, 190),         // physical mm
  improve: false,
));
```

### File upload

```dart
Stream<FileUploadProgress> uploadFile(Uint8List fileData, String devicePath);
void cancelUpload();
```

`uploadFile` computes the SHA-256, copies to native memory on a background
isolate, then streams progress. The returned stream completes on device success
and **throws** `EapException` on failure/timeout (the timeout scales with file
size: 3 min + 5 s/MB). Chunking and the StartFile/FileData/EndFile sequence are
handled natively.

```dart
await for (final p in client.uploadFile(bytes, '/data/model.bin')) {
  print('${(p.sendProgress * 100).toStringAsFixed(0)}%  device=${p.deviceProgress}%');
}
```

### Device logging & diagnostics

`enableDeviceLogging(true)` streams the firmware's own log lines (severity
Information and above) to `deviceLogStream`. Separately, `logStream` always
carries diagnostics from the Dart/FFI layer — handy for an in-app console.
Both deliver `EapLogMessage`.

---

## Riverpod providers

Import `package:flutter_eap/flutter_eap_providers.dart`. All providers are
`keepAlive` and share a single `EapClient` that survives hot restart.

| Provider | Type | Description |
|----------|------|-------------|
| `eapClientProvider` | `EapClient` | The singleton client (initialized for you). |
| `eapClientInstanceProvider` | `EapClient` | Underlying notifier; `eapClientProvider` proxies it. |
| `eapControlProvider` | `EapControl` | Client as the control interface. |
| `eapGazeProvider` | `EapGaze` | Client as the gaze interface. |
| `eapPositioningProvider` | `EapPositioning` | Client as the positioning interface. |
| `eapVersionProvider` | `EapVersion` | Client as the version interface. |
| `eapVideoProvider` | `EapVideo` | Client as the video interface. |
| `eapCalibrationProvider` | `EapCalibration` | Client as the calibration interface. |
| `eapDeviceLoggingProvider` | `EapDeviceLogging` | Client as the device-logging interface. |
| `eapGazeDataStreamProvider` | `Stream<GazesData>` | Gaze frames. |
| `eapPositioningDataStreamProvider` | `Stream<FaceData>` | Positioning frames. |
| `eapVideoDataStreamProvider` | `Stream<VideoFrame>` | Video frames. |
| `eapConnectionStateStreamProvider` | `Stream<ConnectionState>` | State changes. |
| `eapConnectionStateProvider` | `ConnectionState` | Current state (defaults to `disconnected`). |
| `eapControlDataStreamProvider` | `Stream<ControlData>` | Control updates. |
| `eapCurrentControlDataProvider` | `ControlData` | Latest cached control state. |
| `eapCalibrationStreamProvider` | `Stream<CalibrationMessage>` | Calibration events. |
| `eapVersionDataProvider` | `Future<VersionData>` | Version info (waits for `linkSynced`). |
| `eapErrorStreamProvider` | `Stream<String>` | Error messages. |
| `eapLogStreamProvider` | `Stream<EapLogMessage>` | Dart-layer diagnostics. |
| `eapDeviceLogStreamProvider` | `Stream<EapLogMessage>` | Firmware log lines. |

```dart
class GazeReadout extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaze = ref.watch(eapGazeDataStreamProvider);
    return gaze.when(
      data: (g) => Text('${g.gazeX.toStringAsFixed(0)}, ${g.gazeY.toStringAsFixed(0)}'),
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('$e'),
    );
  }
}
```

---

## Data models

### Gaze

```dart
class GazesData {
  final int timestamp;        // device timestamp (ms)
  final GazeData leftEye;
  final GazeData rightEye;
  final GazeData combined;    // most accurate
  double get gazeX;           // == combined.smoothed.x (screen pixels)
  double get gazeY;           // == combined.smoothed.y (screen pixels)
}

class GazeData {
  final Point2d raw;          // unfiltered
  final Point2d smoothed;     // filtered — recommended for UI
  final GazeType type;        // none / fixation / saccade
}
```

`GazesData` also provides `toBytes()` / `fromBytes()` (a reusable `Float64List`
for zero-allocation IPC at 60 Hz) and `toJson()` / `fromJson()`.

### Positioning

```dart
class FaceData {
  final Rect2d faceRect;      // face bounding box (SCREEN space)
  final EyeData leftEye;      // (IMAGE space)
  final EyeData rightEye;     // (IMAGE space)
  static final FaceData empty;
}

class EyeData {
  final Rect2d boundingRect;  // eye region
  final FeatureData pupil;
  final GlintsData glints;    // .left / .right IR reflections
  final IrisData iris;
}

class FeatureData {           // pupil or a single glint
  final Point2d center;
  final Rect2d boundingRect;
  final RotatedRect ellipse;
}

class IrisData {
  final Point2d center, top, left, right, bottom;  // landmarks
  final double distance;      // camera distance in mm (400–700 optimal)
}
```

### Control & display

```dart
// ControlData is a typedef alias for ControlMessage.
class ControlMessage {
  final bool isStandbyEnabled, isAutoPauseEnabled, isPauseEnabled;
  final TrackingMode trackingMode;
  final int gazeFilter;       // 0–255
  final int fixationFilter;   // 0–255
  final bool isAssistiveTouchEnabled, showTrackingDetails, isHidEnabled, isEthernetEnabled;
  factory ControlMessage.empty();
  ControlData copyWith({ ... });
}

class DisplayInfo {
  final Sizeu resolution;     // pixels
  final Size2d sizeMm;        // physical millimeters
}
```

### Calibration

```dart
class CalibrationConfig {
  final List<int> points;         // point indices, e.g. CalibrationType.five.array
  final List<Point2d> coordinates;// custom positions, or [] for device-chosen
  final Sizeu resolution;         // screen pixels
  final Size2d size;              // physical mm
  final bool improve;             // improve existing vs. fresh calibration
}

class CalibrationPoint    { final int index; final Point2d coordinates; }
class CalibrationProgress { final int index; final int progress; /* 0–100 */ }

class CalibrationQualityPoint {
  final int index;
  final Point2d accuracy;   // offset to target
  final double precision;   // precision radius
  final int quality;        // 0–255
}
class CalibrationResult {
  final List<CalibrationQualityPoint> left;
  final List<CalibrationQualityPoint> right;
}
```

### Version, video, files, logging

```dart
class VersionData {
  final String firmware;          // e.g. "3.1.0"
  final BigInt serial;            // unsigned 64-bit
  final bool isDemoDevice;
  final int deviceType, devicePlatform, deviceGeneration;
  final String protocolVersion;   // "" on firmware predating versioning
}

class VideoFrame {
  final int width, height, channels;
  final Uint8List pixelData;
}

class FileUploadStatus {          // raw device status (fileStatusStream)
  final FileTransferStatus status;
  final int progress;             // 0–100 when .isProgress
  final String? errorMessage;     // when .isFailed
  bool get isSuccess, isFailed, isProgress;
}

class FileUploadProgress {        // richer view from uploadFile()
  final int bytesSent, totalBytes, chunksSent, totalChunks;
  final int? deviceProgress;
  final FileTransferStatus? deviceStatus;
  final String? errorMessage;
  double get sendProgress;        // 0.0–1.0
  bool get allChunksSent, isComplete, isFailed;
}

class EapLogMessage {
  final LogLevel level;
  final String source;            // e.g. "EapClient", or "device" for firmware lines
  final String message;
  final DateTime timestamp;
}
```

### Base geometry types

```dart
class Point2d   { double get x, y; bool isZero(); void scale(double); }
class Size2d    { final double width, height; }
class Sizeu     { final int width, height; }          // uint16 dimensions
class Rect2d    { final double left, top, right, bottom;
                  double get width, height; Point2d get center, topLeft, bottomRight; Size2d get size; }
class RotatedRect { final Point2d center; final Size2d size; final double angle; /* degrees */ }
```

Most models also provide `toJson()` / `fromJson()` and a readable `toString()`.

---

## Enumerations

### `ConnectionState`

`disconnected` (0), `waitingPing` (1), `handshakeSent` (2), `waitingSyn` (3),
`synAckSent` (4), `connected` (5), `waitingStartEapAck` (6), `linkSynced` (7),
`error` (8). Helpers: `isReady` (== `linkSynced`), `isConnected` (any state
except `disconnected`/`error`).

> On iOS, ExternalAccessory handles iAP2, so the state jumps straight to
> `linkSynced`.

### `GazeType`

`none` (0), `fixation` (1), `saccade` (2).

### `TrackingMode`

`binocular` (0), `left` (1), `right` (2).

### `CalibrationType`

`one` (1), `two` (2), `five` (5), `nine` (9). `.array` gives the point-index
layout (e.g. `five.array == [0, 2, 6, 8, 4]`).

### `FileTransferStatus`

`success` (0), `progress` (1), `failed` (2).

### `LogLevel`

`trace`, `debug`, `information`, `warning`, `error`, `critical`, `none`.

---

## Coordinate systems

**Never mix coordinate spaces.** Different fields live in different spaces:

| Space | Units | Used by |
|-------|-------|---------|
| **Screen** | Display pixels (0 … screen w/h) | Gaze positions, `FaceData.faceRect`, calibration points |
| **Image** | Camera pixels (~0–2464 × 0–2064) | Eye rects, pupils, glints, iris landmarks |
| **Distance** | Millimeters | `IrisData.distance` (400–700 mm optimal) |

```dart
// WRONG — screen vs image space
if (gaze.gazeX > face.leftEye.iris.center.x) { ... }
// RIGHT — same space
if (gaze.gazeX > face.faceRect.center.x) { ... }
```

---

## Threading & errors

- **Streams are broadcast and already marshalled to the platform isolate** — you
  can update UI directly from their listeners.
- **`VideoFrame.pixelData` is a copy you own**; the other stream payloads are
  plain Dart objects, safe to retain.
- Methods that hit the native layer throw **`EapException`** (with a `message`)
  on failure. `enable*` / calibration / control methods additionally short-circuit
  (log a warning, return) when the client is not `isReady`.

```dart
class EapException implements Exception {
  final String message;
}
```

---

Questions or device access: **support@eyev.de**.
