/// Riverpod providers for EAP client
/// Optional - you can also use EapClient directly without Riverpod
library;

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../eap_client.dart';
import '../models/models.dart';

part 'eap_providers.g.dart';

/// Singleton EAP client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.
@Riverpod(keepAlive: true)
class EapClientInstance extends _$EapClientInstance {
  /// Static instance persists across hot restarts
  static EapClient? _instance;

  @override
  EapClient build() {
    if (_instance != null) {
      debugPrint('eapClient: Returning existing instance ${_instance.hashCode}');
      return _instance!;
    }

    final client = EapClient();
    _instance = client;
    debugPrint('eapClient: Set _instance to ${client.hashCode}');

    client.initialize();
    debugPrint('eapClient: Client initialized');

    return client;
  }

}

/// Convenience provider for backwards compatibility
@Riverpod(keepAlive: true)
EapClient eapClient(Ref ref) {
  return ref.watch(eapClientInstanceProvider);
}

@Riverpod(keepAlive: true)
EapControl eapControl(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapControl;
}

@Riverpod(keepAlive: true)
EapGaze eapGaze(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapGaze;
}

@Riverpod(keepAlive: true)
EapPositioning eapPositioning(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapPositioning;
}

@Riverpod(keepAlive: true)
EapVersion eapVersion(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapVersion;
}

@Riverpod(keepAlive: true)
EapCalibration eapCalibration(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapCalibration;
}

@Riverpod(keepAlive: true)
EapDeviceLogging eapDeviceLogging(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapDeviceLogging;
}

/// Stream provider for gaze data
@Riverpod(keepAlive: true)
Stream<GazesData> eapGazeDataStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.gazeDataStream;
}

/// Stream provider for positioning data
@Riverpod(keepAlive: true)
Stream<FaceData> eapPositioningDataStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.positioningDataStream;
}

/// Stream provider for video data (raw pixel frames with dimensions)
@Riverpod(keepAlive: true)
Stream<VideoFrame> eapVideoDataStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.videoDataStream;
}

@Riverpod(keepAlive: true)
EapVideo eapVideo(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client as EapVideo;
}

/// Stream provider for connection state
@Riverpod(keepAlive: true)
Stream<ConnectionState> eapConnectionStateStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.stateStream;
}

/// Current connection state (from stream)
@Riverpod(keepAlive: true)
ConnectionState eapConnectionState(Ref ref) {
  return ref.watch(eapConnectionStateStreamProvider).value ?? ConnectionState.disconnected;
}

/// Stream provider for control data
@Riverpod(keepAlive: true)
Stream<ControlData> eapControlDataStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.controlDataStream;
}

/// Current control data
@Riverpod(keepAlive: true)
ControlData eapCurrentControlData(Ref ref) {
  ref.watch(eapControlDataStreamProvider);
  final client = ref.watch(eapClientProvider);
  return client.controlData;
}

/// Stream provider for calibration messages
@Riverpod(keepAlive: true)
Stream<CalibrationMessage> eapCalibrationStream(Ref ref) async* {
  final client = ref.watch(eapClientProvider);
  yield* client.calibrationStream;
}

/// Future provider for version info - waits for connection before requesting
@Riverpod(keepAlive: true)
Future<VersionData> eapVersionData(Ref ref) async {
  final connectionState = ref.watch(eapConnectionStateProvider);
  if (!connectionState.isReady) {
    // Wait for linkSynced state via stream
    final client = ref.watch(eapClientProvider);
    await client.stateStream.firstWhere((s) => s.isReady);
  }
  final client = ref.read(eapClientProvider);
  return client.requestVersion();
}

/// Stream provider for errors
@Riverpod(keepAlive: true)
Stream<String> eapErrorStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.errorStream;
}

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [eapDeviceLogStreamProvider], which carries firmware log lines.
@Riverpod(keepAlive: true)
Stream<EapLogMessage> eapLogStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.logStream;
}

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [EapDeviceLogging.enableDeviceLogging] has been turned on.
@Riverpod(keepAlive: true)
Stream<EapLogMessage> eapDeviceLogStream(Ref ref) {
  final client = ref.watch(eapClientProvider);
  return client.deviceLogStream;
}
