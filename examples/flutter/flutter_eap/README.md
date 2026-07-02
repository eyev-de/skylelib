# flutter_eap

High-performance Flutter plugin for Skyle eye-tracking device communication using the EAP (External Accessory Protocol) over iAP2/USB.

## Features

- **Native Performance**: C library via FFI for low-latency communication
- **Real-time Streaming**: Gaze (60Hz) and positioning data (30Hz)
- **Complete Protocol**: Full iAP2/EAP protocol implementation
- **Cross-platform**: Android (USB Host), iOS (ExternalAccessory), macOS (IOKit)
- **Calibration**: Interactive 5/9-point calibration workflow
- **Video Streaming**: Raw camera frames via chunked transfer
- **File Upload**: Chunked file transfer with progress tracking
- **Riverpod Integration**: Providers for reactive state management
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

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_eap/flutter_eap.dart';

class GazeWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gazeAsync = ref.watch(eapGazeDataStreamProvider);

    return gazeAsync.when(
      data: (gaze) => Text('Gaze: (${gaze.gazeX}, ${gaze.gazeY})'),
      loading: () => CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
```

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

| Provider | Type | Description |
|----------|------|-------------|
| `eapClientProvider` | `EapClient` | Singleton client instance |
| `eapGazeDataStreamProvider` | `Stream<GazesData>` | Gaze stream |
| `eapPositioningDataStreamProvider` | `Stream<FaceData>` | Positioning stream |
| `eapVideoDataStreamProvider` | `Stream<VideoFrame>` | Video stream |
| `eapConnectionStateProvider` | `ConnectionState` | Current state |
| `eapConnectionStateStreamProvider` | `Stream<ConnectionState>` | State changes |
| `eapControlDataStreamProvider` | `Stream<ControlData>` | Control data |
| `eapCurrentControlDataProvider` | `ControlData` | Cached control state |
| `eapCalibrationStreamProvider` | `Stream<CalibrationMessage>` | Calibration events |
| `eapVersionDataProvider` | `Future<VersionData>` | Version (waits for linkSynced) |
| `eapErrorStreamProvider` | `Stream<String>` | Error messages |

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

## Platform Support

| Platform | Status | USB API | I/O Model |
|----------|--------|---------|-----------|
| Android | Supported | USB Host API | Pull (JNI) |
| iOS | Supported | ExternalAccessory | Push |
| macOS | Supported | IOKit | Pull (C) |
| Windows | Planned | WinUSB | Pull |
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
