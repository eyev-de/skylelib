# flutter_eap

High-performance Flutter plugin for Skyle eye-tracking device communication using the EAP (External Accessory Protocol) over iAP2/USB.

📖 **[Documentation.md](Documentation.md)** — the full public Dart API reference
(`EapClient`, streams, control settings, calibration, file upload and data
models). Riverpod providers live in the sibling
[flutter_eap_riverpod](../flutter_eap_riverpod) package.

## Features

- **Native Performance**: C library via FFI for low-latency communication
- **Real-time Streaming**: Gaze (60Hz) and positioning data (30Hz)
- **Complete Protocol**: Full iAP2/EAP protocol implementation
- **Cross-platform**: Android (USB Host), iOS (ExternalAccessory), macOS (IOKit), Windows (WinUSB)
- **Multi-engine**: every Flutter engine in a process gets its own callback subscription on the pull-mode platforms (see below)
- **Calibration**: Interactive 5/9-point calibration workflow
- **Video Streaming**: Raw camera frames via chunked transfer
- **File Upload**: Chunked file transfer with progress tracking
- **State-manager agnostic**: Plain Dart streams; Riverpod providers available
  separately in [flutter_eap_riverpod](../flutter_eap_riverpod)
- **Type-safe API**: Comprehensive data models and error handling

## Architecture

```
Dart Layer (UI/Business Logic)
    | FFI (NativeCallable.listener for callbacks, direct calls for commands)
    v
C Bridge Layer (platform-specific adapter)
    | transport_read / transport_write function pointers
    v
Platform USB Layer
    iOS:     ExternalAccessory (push mode, no background thread)
    Android: USB Host API (pull mode, JNI callbacks)
    macOS:   IOKit (pull mode, pure C)
    | USB bulk endpoints (IN=0x82, OUT=0x02)
    v
Skyle Eye-Tracker (VID=0x3729, PID=0x7333)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed platform-specific transport documentation.

### Multi-engine callback fan-out

On all pull-mode platforms (Android, macOS, Windows, Linux) the plugin fans
every message callback out to multiple Flutter engines in one process (main
window + overlay/sub-window engines): each engine registers its own subscriber
on the shared native client and receives all callbacks independently, with
per-subscriber payload copies (shared module: `native/fanout/`). Stale
subscribers from a hot-restarted engine are reaped automatically - on Android
by the Kotlin plugin's handle bookkeeping, on desktop natively: Dart passes
the engine id (`PlatformDispatcher.engineId`, stable across hot restarts) to
`flutter_eap_add_callbacks_engine`, and a re-add with the same token replaces
the previous subscriber. The former desktop primary/passive engine guard
(`flutter_eap_try_acquire_primary`) is gone - with per-engine subscribers
there is no single callback slot to protect, and sub-window engines get live
streams instead of attaching passively. iOS keeps the single-slot push-mode
flow (one engine, `flutter_eap_set_callbacks`).

## Quick Start

### Installation

Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter_eap:
    path: ../packages/flutter_eap
```

### Android Configuration

In `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 24  // USB Host API requires API 24+
    }
}
```

Add USB permissions to `AndroidManifest.xml`:
```xml
<uses-feature android:name="android.hardware.usb.host" />
<uses-permission android:name="android.permission.USB_PERMISSION" />
```

### Basic Usage

```dart
import 'package:flutter_eap/flutter_eap.dart';

// Initialize client
final client = EapClient();
client.initialize();

// Listen to connection state
client.stateStream.listen((state) {
  if (state.isReady) {
    // Ready to communicate - enable features
    client.enableGaze(true);
  }
});

// Listen to gaze data
client.gazeDataStream.listen((gaze) {
  print('Gaze: (${gaze.gazeX}, ${gaze.gazeY})');
});

// Connect to device
client.connect();

// Cleanup
client.disconnect();
client.dispose();
```

### Riverpod Integration

Riverpod providers moved to the sibling
[flutter_eap_riverpod](../flutter_eap_riverpod) package, so apps using other
state managers can depend on flutter_eap alone. Depend on
`flutter_eap_riverpod` and import
`package:flutter_eap_riverpod/flutter_eap_riverpod.dart` (it re-exports the
full flutter_eap API); see its README for the provider list.

## API Reference

### EapClient

#### Lifecycle
```dart
void initialize()            // Initialize FFI bindings (call once)
void dispose()               // Cleanup resources
void connect()               // Connect to device
void disconnect()            // Disconnect from device
```

#### State
```dart
ConnectionState get state    // Current connection state
bool get isReady             // True when linkSynced (ready for messages)
bool get isConnected         // True if in any connected state
Stream<ConnectionState> get stateStream
Stream<String> get errorStream
```

#### Data Streams
```dart
Stream<GazesData> get gazeDataStream           // 60Hz when enabled
Stream<FaceData> get positioningDataStream      // 30Hz when enabled
Stream<VideoFrame> get videoDataStream          // Video frames when enabled
Stream<ControlData> get controlDataStream       // Device settings
Stream<CalibrationMessage> get calibrationStream
```

#### Commands
```dart
void enableGaze(bool enable)
void enablePositioning(bool enable)
void enableVideo(bool enable)
void enableControl(bool enable)
Future<VersionData> requestVersion()
void sendControl(ControlMessage message)
```

#### Control Properties (read/write)
```dart
bool isStandbyEnabled
bool isAutoPauseEnabled
bool isPauseEnabled
TrackingMode trackingMode        // binocular, left, right
int gazeFilter                   // 0-255
int fixationFilter               // 0-255
bool isAssistiveTouchEnabled
bool showTrackingDetails
bool isHidEnabled
bool isEthernetEnabled
void defaultFilter()             // gazeFilter=5, fixationFilter=30
```

#### Calibration
```dart
void startCalibration(CalibrationConfig config)
void collectCalibrationPoints()  // Signal ready for next point
void abortCalibration()
```

#### File Upload
```dart
Stream<FileUploadProgress> uploadFile(Uint8List data, String devicePath)
void cancelUpload()
```

### Riverpod Providers

Moved to the sibling [flutter_eap_riverpod](../flutter_eap_riverpod) package;
its README lists all providers.

## Data Models

### GazesData
```dart
class GazesData {
  final ComplexGaze leftEye;   // Left eye gaze
  final ComplexGaze rightEye;  // Right eye gaze
  final ComplexGaze combined;  // Combined (most accurate)
  double get gazeX;            // Screen X (pixels, from combined.smoothed)
  double get gazeY;            // Screen Y (pixels, from combined.smoothed)
}

class ComplexGaze {
  final Point2d raw;           // Unfiltered position
  final Point2d smoothed;      // Filtered (recommended for UI)
  final GazeType type;         // fixation / saccade / unknown
}
```

### FaceData (Positioning)
```dart
class FaceData {
  final Rect2d faceRect;       // Face bounding box (screen space)
  final EyeData leftEye;       // Left eye features (image space)
  final EyeData rightEye;      // Right eye features (image space)
}

class EyeData {
  final Rect2d boundingRect;   // Eye region
  final Feature pupil;         // Pupil ellipse
  final Feature leftGlint;     // IR reflections
  final Feature rightGlint;
  final IrisData iris;         // Iris landmarks + distance in mm
}
```

### ConnectionState (9 states)
```dart
enum ConnectionState {
  disconnected,         // No connection
  waitingPing,          // Sent initial RST
  handshakeSent,        // Detection bytes sent
  waitingSyn,           // Waiting for device SYN
  synAckSent,           // SYN-ACK sent
  connected,            // iAP2 link up
  waitingStartEapAck,   // Waiting for EAP session ACK
  linkSynced,           // Ready for application messages
  error                 // Connection error
}
```

Note: On iOS, ExternalAccessory handles iAP2 so the state jumps directly to `linkSynced`.

## Coordinate Systems

**CRITICAL**: Different data types use different coordinate systems. Never mix them!

| Space | Units | Used By |
|-------|-------|---------|
| **Screen** | Display pixels (0 to screen width/height) | Gaze positions, face rect, calibration points |
| **Image** | Camera pixels (~0-2464 x 0-2064) | Eye rects, pupils, glints, iris landmarks |
| **Distance** | Millimeters | `IrisData.distanceMm` (400-700mm optimal) |

```dart
// WRONG - comparing screen space with image space
if (gazeData.gazeX > positioning.leftEye.iris.center.x) { ... }

// CORRECT - same coordinate system
if (gazeData.gazeX > positioning.faceRect.center.x) { ... }
```

## Skyle Link: multi-app sharing

Skyle Link lets multiple applications on one machine share a single Skyle eye
tracker. Exactly one process owns the USB link (the "hub") and serves the EAP
data on a localhost TCP port; every other application connects as a
"local-link client" and uses the unchanged `EapClient` API. Protocol details:
`docs/SKYLE_LINK_PROTOCOL.md` in the skylelib repository.

### Automatic transport selection

There is nothing to select: the native transport supervisor elects the hub
owner among the local apps, dials as a client otherwise, and swaps a running
session live between USB and socket on handovers/preemption. Applications
only observe a short DISCONNECTED -> LINK_SYNCED blip and only ever supply an
identity (HELLO app id + priority tier; lower tier = higher priority, tier 0
is reserved for Skyle X).

**Desktop (macOS/Windows/Linux)** - pass the identity to `initialize`, or set
the static default before anything (e.g. a Riverpod provider) initializes the
client:

```dart
// Explicit:
final client = EapClient();
client.initialize(identity: const SkyleLinkIdentity(appId: 'my-aac-app', priorityTier: SkyleLinkTier.partner));

// Or early in main(), when something else calls initialize():
EapClient.defaultIdentity = const SkyleLinkIdentity(appId: 'my-aac-app', priorityTier: SkyleLinkTier.partner);
```

A bare `initialize()` with no default set runs with the native defaults
(third-party app id, default tier) - fully functional as a client app.

**Android** - the platform layer owns identity and supervisor; Dart-side
identities are ignored. Skyle X's process-wide USB host publishes the skylex
identity itself. SDK client apps configure everything via application-level
manifest meta-data:

```xml
<application>
    <!-- Never claim USB / the skylex identity from an engine attach: -->
    <meta-data
        android:name="de.eyev.flutter_eap.AUTO_START_USB_HOST"
        android:value="false" />
    <!-- Skyle Link identity (defaults: packageName, tier 2): -->
    <meta-data
        android:name="de.eyev.flutter_eap.APP_ID"
        android:value="my-aac-app" />
    <meta-data
        android:name="de.eyev.flutter_eap.PRIORITY_TIER"
        android:value="1" />
</application>
```

**iOS** - the supervisor is disabled (exclusive ExternalAccessory session);
`initialize(identity:)` is a no-op there.

### Suspension

Any local-link client can suspend eye control (Skyle X hides its gaze UI and
stops synthesizing input) while it needs the screen for itself:

```dart
await client.setEyeControlSuspended(true);   // take the lease
// ... later
await client.setEyeControlSuspended(false);  // release it
```

All participants observe `client.suspensionStream` (seed from
`client.currentSuspensionState`); `flutter_eap_riverpod` exposes this as
`eapSuspensionProvider`. The lease dies with the holder's connection.

### Orderly quit (Android)

`EapClient.stopUsbHost()` disables the supervisor (BYE(handover) to all hub
clients), releases the USB device, and clears native host ownership so a
waiting app can take the tracker over. Eye control stays off until the next
`EapUsbHost.start` (app relaunch / service rebind).

### Client app requirements (Android)

- Declare the `INTERNET` permission (localhost sockets require it):
  `<uses-permission android:name="android.permission.INTERNET" />`
- Set `AUTO_START_USB_HOST` to `false` as shown above (the default `true`
  keeps existing owner apps like Skyle X unchanged).

### Client app requirements (macOS)

A sandboxed app needs BOTH network entitlements in its .entitlements files:
`com.apple.security.network.client` (dialing another app's hub - without it
the sandbox denies every connect() with EPERM, indistinguishable from
"connection refused") and `com.apple.security.network.server` (serving the
hub as owner), plus `com.apple.security.device.usb` for the tracker itself.

The method channel also offers `hasUsbPermission` (tracker attached AND USB
permission held - no dialog), the supervisor's election eligibility check.

## Platform Support

| Platform | Status | USB API | I/O Model |
|----------|--------|---------|-----------|
| Android | Supported | USB Host API | Pull (JNI) |
| iOS | Supported | ExternalAccessory | Push |
| macOS | Supported | IOKit | Pull (C) |
| Windows | Supported | WinUSB | Pull (C) |
| Linux | Planned | USB | Pull |

### Requirements
- **Android**: Min SDK 24, NDK 23.1.7779620, CMake 3.22.1+
- **iOS**: iOS 12.0+, MFi protocol `de.eyev.eap`
- **macOS**: macOS 10.15+

## Device

- **Vendor ID**: 0x3729
- **Product ID**: 0x7333
- **Protocol**: EAP over iAP2/USB
- **Endpoints**: Bulk IN (0x82), Bulk OUT (0x02)

## Example App

The `example/` directory contains a complete demonstration. Run with:
```bash
cd example
flutter run
```

## Troubleshooting

### Device Not Found
- Check USB connection and verify VID/PID (0x3729:0x7333)
- Grant USB permissions on Android
- Check `errorStream` for detailed messages

### No Data Streaming
- Ensure `state == ConnectionState.linkSynced` before enabling streams
- Call `enableGaze(true)` / `enablePositioning(true)` explicitly

### Build Errors
- Install CMake and NDK via Android Studio SDK Manager
- Run `flutter clean && flutter pub get`

## License

The flutter_eap plugin source code is licensed under the
[MIT License](LICENSE). The prebuilt skylelib binaries it downloads at
build time are proprietary software of eyeV GmbH, licensed under the
terms shipped inside each SDK archive.
