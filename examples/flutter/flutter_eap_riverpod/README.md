# flutter_eap_riverpod

Riverpod providers for the [flutter_eap](../flutter_eap) Skyle eye-tracker
plugin. Split into its own package so apps using other state managers can
depend on `flutter_eap` alone, without pulling in Riverpod.

## Usage

```yaml
dependencies:
  flutter_eap_riverpod:
    git:
      url: https://github.com/eyev-de/skylelib.git
      ref: vX.Y.Z
      path: examples/flutter/flutter_eap_riverpod
  flutter_riverpod: ^3.0.0
```

The package re-exports the full `flutter_eap` API, so a single import covers
the client, the data models, and the providers:

```dart
import 'package:flutter_eap_riverpod/flutter_eap_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GazeView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaze = ref.watch(eapGazeDataStreamProvider);
    final state = ref.watch(eapConnectionStateProvider);
    // ...
  }
}
```

## Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `eapClientProvider` | `EapClient` | Singleton client (survives hot restart) |
| `eapConnectionStateProvider` | `ConnectionState` | Current connection state |
| `eapConnectionStateStreamProvider` | `Stream<ConnectionState>` | Connection state changes |
| `eapGazeDataStreamProvider` | `Stream<GazesData>` | Gaze points |
| `eapPositioningDataStreamProvider` | `Stream<FaceData>` | Face/eye positioning |
| `eapVideoDataStreamProvider` | `Stream<VideoFrame>` | Video frames |
| `eapControlDataStreamProvider` | `Stream<ControlData>` | Control/settings updates |
| `eapCurrentControlDataProvider` | `ControlData` | Latest control data |
| `eapCalibrationStreamProvider` | `Stream<CalibrationMessage>` | Calibration workflow messages |
| `eapVersionDataProvider` | `Future<VersionData>` | Device version (waits for link) |
| `eapErrorStreamProvider` | `Stream<String>` | Error messages |
| `eapLogStreamProvider` | `Stream<EapLogMessage>` | Dart-layer diagnostic log |
| `eapDeviceLogStreamProvider` | `Stream<EapLogMessage>` | Firmware log lines |

Capability-scoped accessors are also exposed (`eapControlProvider`,
`eapGazeProvider`, `eapPositioningProvider`, `eapVideoProvider`,
`eapVersionProvider`, `eapCalibrationProvider`, `eapDeviceLoggingProvider`).

## Codegen

Providers use `riverpod_generator`, and the generated `eap_providers.g.dart`
is checked in so git consumers do not need to run codegen. After changing
`lib/src/eap_providers.dart`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Requires Flutter SDK >= 3.44: `riverpod_generator >= 4.0.4` (needed for
riverpod 3.3.x-compatible output) does not resolve on older SDKs, and older
generators emit code that will not compile against riverpod 3.3.x. After
regenerating, verify the example app still builds — it resolves the riverpod
version consumers actually get.
