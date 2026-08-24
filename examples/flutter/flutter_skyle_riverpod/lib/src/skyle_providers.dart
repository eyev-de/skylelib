/// Riverpod providers for the Skyle client
/// Optional - you can also use SkyleClient directly without Riverpod
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_skyle/flutter_skyle.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'skyle_providers.g.dart';

/// Singleton Skyle client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.
@Riverpod(keepAlive: true)
class SkyleClientInstance extends _$SkyleClientInstance {
  /// Static instance persists across hot restarts
  static SkyleClient? _instance;

  @override
  SkyleClient build() {
    if (_instance != null) {
      debugPrint('skyleClient: Returning existing instance ${_instance.hashCode}');
      return _instance!;
    }

    final client = SkyleClient();
    _instance = client;
    debugPrint('skyleClient: Set _instance to ${client.hashCode}');

    client.initialize();
    debugPrint('skyleClient: Client initialized');

    return client;
  }

}

/// Convenience provider for backwards compatibility
@Riverpod(keepAlive: true)
SkyleClient skyleClient(Ref ref) {
  return ref.watch(skyleClientInstanceProvider);
}

@Riverpod(keepAlive: true)
SkyleControl skyleControl(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleControl;
}

@Riverpod(keepAlive: true)
SkyleGaze skyleGaze(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleGaze;
}

@Riverpod(keepAlive: true)
SkylePositioning skylePositioning(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkylePositioning;
}

@Riverpod(keepAlive: true)
SkyleVersion skyleVersion(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleVersion;
}

@Riverpod(keepAlive: true)
SkyleCalibration skyleCalibration(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleCalibration;
}

@Riverpod(keepAlive: true)
SkyleDeviceLogging skyleDeviceLogging(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleDeviceLogging;
}

/// Stream provider for gaze data
@Riverpod(keepAlive: true)
Stream<GazesData> skyleGazeDataStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.gazeDataStream;
}

/// Stream provider for positioning data
@Riverpod(keepAlive: true)
Stream<FaceData> skylePositioningDataStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.positioningDataStream;
}

/// Stream provider for video data (raw pixel frames with dimensions)
@Riverpod(keepAlive: true)
Stream<VideoFrame> skyleVideoDataStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.videoDataStream;
}

@Riverpod(keepAlive: true)
SkyleVideo skyleVideo(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client as SkyleVideo;
}

/// Stream provider for connection state.
/// Seeded with the current native state: after an in-process engine recreation
/// (hot restart, activity relaunch) the native client may already be
/// LINK_SYNCED and the stream alone would never emit for this engine.
@Riverpod(keepAlive: true)
Stream<ConnectionState> skyleConnectionStateStream(Ref ref) async* {
  final client = ref.watch(skyleClientProvider);
  yield client.currentState;
  yield* client.stateStream;
}

/// Stream provider for the Skyle Link eye-control suspension state.
/// Seeded with the current native cached state (a suspension may already be
/// active when this engine subscribes), then follows every change broadcast
/// by the hub / local link.
@Riverpod(keepAlive: true)
Stream<SkyleLinkSuspendState> skyleSuspension(Ref ref) async* {
  final client = ref.watch(skyleClientProvider);
  yield client.currentSuspensionState;
  yield* client.suspensionStream;
}

/// Stream provider for Skyle Link HOST_CONTROL commands received while this
/// process serves the hub. Commands, not state - deliberately unseeded
/// (unlike [skyleSuspension] there is nothing to seed from).
@Riverpod(keepAlive: true)
Stream<SkyleLinkHostControl> skyleHostControl(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.hostControlStream;
}

/// Stream provider for Skyle Link hub client presence changes
/// (connect/disconnect) while this process serves the hub. Events, not
/// state - deliberately unseeded; disconnects carry the app id a
/// restore-on-disconnect policy keys on.
@Riverpod(keepAlive: true)
Stream<SkyleLinkClientEvent> skyleLinkClients(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.linkClientStream;
}

/// Current connection state (from stream)
@Riverpod(keepAlive: true)
ConnectionState skyleConnectionState(Ref ref) {
  return ref.watch(skyleConnectionStateStreamProvider).value ?? ConnectionState.disconnected;
}

/// Stream provider for control data
@Riverpod(keepAlive: true)
Stream<ControlData> skyleControlDataStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.controlDataStream;
}

/// Current control data
@Riverpod(keepAlive: true)
ControlData skyleCurrentControlData(Ref ref) {
  ref.watch(skyleControlDataStreamProvider);
  final client = ref.watch(skyleClientProvider);
  return client.controlData;
}

/// Stream provider for calibration messages
@Riverpod(keepAlive: true)
Stream<CalibrationMessage> skyleCalibrationStream(Ref ref) async* {
  final client = ref.watch(skyleClientProvider);
  yield* client.calibrationStream;
}

/// Future provider for version info - waits for connection before requesting
@Riverpod(keepAlive: true)
Future<VersionData> skyleVersionData(Ref ref) async {
  final connectionState = ref.watch(skyleConnectionStateProvider);
  if (!connectionState.isReady) {
    // Wait for linkSynced state via stream
    final client = ref.watch(skyleClientProvider);
    await client.stateStream.firstWhere((s) => s.isReady);
  }
  final client = ref.read(skyleClientProvider);
  return client.requestVersion();
}

/// Stream provider for errors
@Riverpod(keepAlive: true)
Stream<String> skyleErrorStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.errorStream;
}

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [skyleDeviceLogStreamProvider], which carries firmware log lines.
@Riverpod(keepAlive: true)
Stream<SkyleLogMessage> skyleLogStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.logStream;
}

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [SkyleDeviceLogging.enableDeviceLogging] has been turned on.
@Riverpod(keepAlive: true)
Stream<SkyleLogMessage> skyleDeviceLogStream(Ref ref) {
  final client = ref.watch(skyleClientProvider);
  return client.deviceLogStream;
}
