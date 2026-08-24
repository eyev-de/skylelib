# flutter_skyle_riverpod

Riverpod providers for the [flutter_skyle](../flutter_skyle) Skyle eye-tracker
plugin. Split into its own package so apps using other state managers can
depend on `flutter_skyle` alone, without pulling in Riverpod.

## Usage

```yaml
dependencies:
  flutter_skyle_riverpod:
    git:
      url: https://github.com/eyev-de/skylelib.git
      ref: vX.Y.Z
      path: examples/flutter/flutter_skyle_riverpod
  flutter_riverpod: ^3.0.0
```

The package re-exports the full `flutter_skyle` API, so a single import covers
the client, the data models, and the providers:

```dart
import 'package:flutter_skyle_riverpod/flutter_skyle_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GazeView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaze = ref.watch(skyleGazeDataStreamProvider);
    final state = ref.watch(skyleConnectionStateProvider);
    // ...
  }
}
```

## Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `skyleClientProvider` | `SkyleClient` | Singleton client (survives hot restart) |
| `skyleConnectionStateProvider` | `ConnectionState` | Current connection state |
| `skyleConnectionStateStreamProvider` | `Stream<ConnectionState>` | Connection state changes |
| `skyleGazeDataStreamProvider` | `Stream<GazesData>` | Gaze points |
| `skylePositioningDataStreamProvider` | `Stream<FaceData>` | Face/eye positioning |
| `skyleVideoDataStreamProvider` | `Stream<VideoFrame>` | Video frames |
| `skyleControlDataStreamProvider` | `Stream<ControlData>` | Control/settings updates |
| `skyleCurrentControlDataProvider` | `ControlData` | Latest control data |
| `skyleCalibrationStreamProvider` | `Stream<CalibrationMessage>` | Calibration workflow messages |
| `skyleVersionDataProvider` | `Future<VersionData>` | Device version (waits for link) |
| `skyleErrorStreamProvider` | `Stream<String>` | Error messages |
| `skyleLogStreamProvider` | `Stream<SkyleLogMessage>` | Dart-layer diagnostic log |
| `skyleDeviceLogStreamProvider` | `Stream<SkyleLogMessage>` | Firmware log lines |

Capability-scoped accessors are also exposed (`skyleControlProvider`,
`skyleGazeProvider`, `skylePositioningProvider`, `skyleVideoProvider`,
`skyleVersionProvider`, `skyleCalibrationProvider`, `skyleDeviceLoggingProvider`).

## Codegen

Providers use `riverpod_generator`, and the generated `skyle_providers.g.dart`
is checked in so git consumers do not need to run codegen. After changing
`lib/src/skyle_providers.dart`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Requires Flutter SDK >= 3.44: `riverpod_generator >= 4.0.4` (needed for
riverpod 3.3.x-compatible output) does not resolve on older SDKs, and older
generators emit code that will not compile against riverpod 3.3.x. After
regenerating, verify the example app still builds — it resolves the riverpod
version consumers actually get.
