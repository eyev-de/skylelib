// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skyle_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Singleton Skyle client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.

@ProviderFor(SkyleClientInstance)
final skyleClientInstanceProvider = SkyleClientInstanceProvider._();

/// Singleton Skyle client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.
final class SkyleClientInstanceProvider
    extends $NotifierProvider<SkyleClientInstance, SkyleClient> {
  /// Singleton Skyle client notifier that preserves state across hot restarts.
  /// Uses a static instance to maintain the USB connection through restarts.
  SkyleClientInstanceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleClientInstanceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleClientInstanceHash();

  @$internal
  @override
  SkyleClientInstance create() => SkyleClientInstance();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleClient>(value),
    );
  }
}

String _$skyleClientInstanceHash() =>
    r'e648fa6dd1bb28a9e9bacf120f3eaef80ef5e894';

/// Singleton Skyle client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.

abstract class _$SkyleClientInstance extends $Notifier<SkyleClient> {
  SkyleClient build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SkyleClient, SkyleClient>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SkyleClient, SkyleClient>,
              SkyleClient,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Convenience provider for backwards compatibility

@ProviderFor(skyleClient)
final skyleClientProvider = SkyleClientProvider._();

/// Convenience provider for backwards compatibility

final class SkyleClientProvider
    extends $FunctionalProvider<SkyleClient, SkyleClient, SkyleClient>
    with $Provider<SkyleClient> {
  /// Convenience provider for backwards compatibility
  SkyleClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleClientHash();

  @$internal
  @override
  $ProviderElement<SkyleClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleClient create(Ref ref) {
    return skyleClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleClient>(value),
    );
  }
}

String _$skyleClientHash() => r'219e387b437f14430447acbaadb678f8fd476cfe';

@ProviderFor(skyleControl)
final skyleControlProvider = SkyleControlProvider._();

final class SkyleControlProvider
    extends $FunctionalProvider<SkyleControl, SkyleControl, SkyleControl>
    with $Provider<SkyleControl> {
  SkyleControlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleControlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleControlHash();

  @$internal
  @override
  $ProviderElement<SkyleControl> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleControl create(Ref ref) {
    return skyleControl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleControl value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleControl>(value),
    );
  }
}

String _$skyleControlHash() => r'6f900bdedcdba6ab4c6968a9f72191ce854d48d8';

@ProviderFor(skyleGaze)
final skyleGazeProvider = SkyleGazeProvider._();

final class SkyleGazeProvider
    extends $FunctionalProvider<SkyleGaze, SkyleGaze, SkyleGaze>
    with $Provider<SkyleGaze> {
  SkyleGazeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleGazeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleGazeHash();

  @$internal
  @override
  $ProviderElement<SkyleGaze> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleGaze create(Ref ref) {
    return skyleGaze(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleGaze value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleGaze>(value),
    );
  }
}

String _$skyleGazeHash() => r'765637085178ce12a5f009fa131880f2bea3826e';

@ProviderFor(skylePositioning)
final skylePositioningProvider = SkylePositioningProvider._();

final class SkylePositioningProvider
    extends
        $FunctionalProvider<
          SkylePositioning,
          SkylePositioning,
          SkylePositioning
        >
    with $Provider<SkylePositioning> {
  SkylePositioningProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skylePositioningProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skylePositioningHash();

  @$internal
  @override
  $ProviderElement<SkylePositioning> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkylePositioning create(Ref ref) {
    return skylePositioning(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkylePositioning value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkylePositioning>(value),
    );
  }
}

String _$skylePositioningHash() => r'39a4767ddcfa0fda50366e59e1f73fdb8ba089d7';

@ProviderFor(skyleVersion)
final skyleVersionProvider = SkyleVersionProvider._();

final class SkyleVersionProvider
    extends $FunctionalProvider<SkyleVersion, SkyleVersion, SkyleVersion>
    with $Provider<SkyleVersion> {
  SkyleVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleVersionHash();

  @$internal
  @override
  $ProviderElement<SkyleVersion> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleVersion create(Ref ref) {
    return skyleVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleVersion value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleVersion>(value),
    );
  }
}

String _$skyleVersionHash() => r'98df063bd5c00da47db0ec01b624df671e72fd73';

@ProviderFor(skyleCalibration)
final skyleCalibrationProvider = SkyleCalibrationProvider._();

final class SkyleCalibrationProvider
    extends
        $FunctionalProvider<
          SkyleCalibration,
          SkyleCalibration,
          SkyleCalibration
        >
    with $Provider<SkyleCalibration> {
  SkyleCalibrationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleCalibrationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleCalibrationHash();

  @$internal
  @override
  $ProviderElement<SkyleCalibration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleCalibration create(Ref ref) {
    return skyleCalibration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleCalibration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleCalibration>(value),
    );
  }
}

String _$skyleCalibrationHash() => r'64944b1cd16dfbaabb31d2bc5f1c0824d5fc358a';

@ProviderFor(skyleDeviceLogging)
final skyleDeviceLoggingProvider = SkyleDeviceLoggingProvider._();

final class SkyleDeviceLoggingProvider
    extends
        $FunctionalProvider<
          SkyleDeviceLogging,
          SkyleDeviceLogging,
          SkyleDeviceLogging
        >
    with $Provider<SkyleDeviceLogging> {
  SkyleDeviceLoggingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleDeviceLoggingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleDeviceLoggingHash();

  @$internal
  @override
  $ProviderElement<SkyleDeviceLogging> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SkyleDeviceLogging create(Ref ref) {
    return skyleDeviceLogging(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleDeviceLogging value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleDeviceLogging>(value),
    );
  }
}

String _$skyleDeviceLoggingHash() =>
    r'7395e226542f32db902c17e903be03bdc6c75757';

/// Stream provider for gaze data

@ProviderFor(skyleGazeDataStream)
final skyleGazeDataStreamProvider = SkyleGazeDataStreamProvider._();

/// Stream provider for gaze data

final class SkyleGazeDataStreamProvider
    extends
        $FunctionalProvider<AsyncValue<GazesData>, GazesData, Stream<GazesData>>
    with $FutureModifier<GazesData>, $StreamProvider<GazesData> {
  /// Stream provider for gaze data
  SkyleGazeDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleGazeDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleGazeDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<GazesData> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<GazesData> create(Ref ref) {
    return skyleGazeDataStream(ref);
  }
}

String _$skyleGazeDataStreamHash() =>
    r'e37804df2fadd7c1d8c18ca34ce780288e4c79c3';

/// Stream provider for positioning data

@ProviderFor(skylePositioningDataStream)
final skylePositioningDataStreamProvider =
    SkylePositioningDataStreamProvider._();

/// Stream provider for positioning data

final class SkylePositioningDataStreamProvider
    extends
        $FunctionalProvider<AsyncValue<FaceData>, FaceData, Stream<FaceData>>
    with $FutureModifier<FaceData>, $StreamProvider<FaceData> {
  /// Stream provider for positioning data
  SkylePositioningDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skylePositioningDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skylePositioningDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<FaceData> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<FaceData> create(Ref ref) {
    return skylePositioningDataStream(ref);
  }
}

String _$skylePositioningDataStreamHash() =>
    r'224238506c6c0cd5715ac6bdca505e4fad97f60f';

/// Stream provider for video data (raw pixel frames with dimensions)

@ProviderFor(skyleVideoDataStream)
final skyleVideoDataStreamProvider = SkyleVideoDataStreamProvider._();

/// Stream provider for video data (raw pixel frames with dimensions)

final class SkyleVideoDataStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<VideoFrame>,
          VideoFrame,
          Stream<VideoFrame>
        >
    with $FutureModifier<VideoFrame>, $StreamProvider<VideoFrame> {
  /// Stream provider for video data (raw pixel frames with dimensions)
  SkyleVideoDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleVideoDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleVideoDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<VideoFrame> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<VideoFrame> create(Ref ref) {
    return skyleVideoDataStream(ref);
  }
}

String _$skyleVideoDataStreamHash() =>
    r'504fae68765273ce1573fc8d6186389b0ea14266';

@ProviderFor(skyleVideo)
final skyleVideoProvider = SkyleVideoProvider._();

final class SkyleVideoProvider
    extends $FunctionalProvider<SkyleVideo, SkyleVideo, SkyleVideo>
    with $Provider<SkyleVideo> {
  SkyleVideoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleVideoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleVideoHash();

  @$internal
  @override
  $ProviderElement<SkyleVideo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SkyleVideo create(Ref ref) {
    return skyleVideo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SkyleVideo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SkyleVideo>(value),
    );
  }
}

String _$skyleVideoHash() => r'39dde5cfe1c0828e2470999a3e15bd27328b97f1';

/// Stream provider for connection state.
/// Seeded with the current native state: after an in-process engine recreation
/// (hot restart, activity relaunch) the native client may already be
/// LINK_SYNCED and the stream alone would never emit for this engine.

@ProviderFor(skyleConnectionStateStream)
final skyleConnectionStateStreamProvider =
    SkyleConnectionStateStreamProvider._();

/// Stream provider for connection state.
/// Seeded with the current native state: after an in-process engine recreation
/// (hot restart, activity relaunch) the native client may already be
/// LINK_SYNCED and the stream alone would never emit for this engine.

final class SkyleConnectionStateStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionState>,
          ConnectionState,
          Stream<ConnectionState>
        >
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
  /// Stream provider for connection state.
  /// Seeded with the current native state: after an in-process engine recreation
  /// (hot restart, activity relaunch) the native client may already be
  /// LINK_SYNCED and the stream alone would never emit for this engine.
  SkyleConnectionStateStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleConnectionStateStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleConnectionStateStreamHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionState> create(Ref ref) {
    return skyleConnectionStateStream(ref);
  }
}

String _$skyleConnectionStateStreamHash() =>
    r'df5c0645dd387e4c26e6aaea5cb8d3aa1b6fc95a';

/// Stream provider for the Skyle Link eye-control suspension state.
/// Seeded with the current native cached state (a suspension may already be
/// active when this engine subscribes), then follows every change broadcast
/// by the hub / local link.

@ProviderFor(skyleSuspension)
final skyleSuspensionProvider = SkyleSuspensionProvider._();

/// Stream provider for the Skyle Link eye-control suspension state.
/// Seeded with the current native cached state (a suspension may already be
/// active when this engine subscribes), then follows every change broadcast
/// by the hub / local link.

final class SkyleSuspensionProvider
    extends
        $FunctionalProvider<
          AsyncValue<SkyleLinkSuspendState>,
          SkyleLinkSuspendState,
          Stream<SkyleLinkSuspendState>
        >
    with
        $FutureModifier<SkyleLinkSuspendState>,
        $StreamProvider<SkyleLinkSuspendState> {
  /// Stream provider for the Skyle Link eye-control suspension state.
  /// Seeded with the current native cached state (a suspension may already be
  /// active when this engine subscribes), then follows every change broadcast
  /// by the hub / local link.
  SkyleSuspensionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleSuspensionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleSuspensionHash();

  @$internal
  @override
  $StreamProviderElement<SkyleLinkSuspendState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SkyleLinkSuspendState> create(Ref ref) {
    return skyleSuspension(ref);
  }
}

String _$skyleSuspensionHash() => r'bc82c4d4d979677414a62f571f63fbf6323b8484';

/// Current connection state (from stream)

@ProviderFor(skyleConnectionState)
final skyleConnectionStateProvider = SkyleConnectionStateProvider._();

/// Current connection state (from stream)

final class SkyleConnectionStateProvider
    extends
        $FunctionalProvider<ConnectionState, ConnectionState, ConnectionState>
    with $Provider<ConnectionState> {
  /// Current connection state (from stream)
  SkyleConnectionStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleConnectionStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleConnectionStateHash();

  @$internal
  @override
  $ProviderElement<ConnectionState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConnectionState create(Ref ref) {
    return skyleConnectionState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionState>(value),
    );
  }
}

String _$skyleConnectionStateHash() =>
    r'463ac5fd0e42578e8d91ba4b86e52ef3b08fc3c4';

/// Stream provider for control data

@ProviderFor(skyleControlDataStream)
final skyleControlDataStreamProvider = SkyleControlDataStreamProvider._();

/// Stream provider for control data

final class SkyleControlDataStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<ControlData>,
          ControlData,
          Stream<ControlData>
        >
    with $FutureModifier<ControlData>, $StreamProvider<ControlData> {
  /// Stream provider for control data
  SkyleControlDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleControlDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleControlDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<ControlData> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ControlData> create(Ref ref) {
    return skyleControlDataStream(ref);
  }
}

String _$skyleControlDataStreamHash() =>
    r'87b3b907e614ee21563c2f683ce08ea399231b50';

/// Current control data

@ProviderFor(skyleCurrentControlData)
final skyleCurrentControlDataProvider = SkyleCurrentControlDataProvider._();

/// Current control data

final class SkyleCurrentControlDataProvider
    extends $FunctionalProvider<ControlData, ControlData, ControlData>
    with $Provider<ControlData> {
  /// Current control data
  SkyleCurrentControlDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleCurrentControlDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleCurrentControlDataHash();

  @$internal
  @override
  $ProviderElement<ControlData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ControlData create(Ref ref) {
    return skyleCurrentControlData(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlData>(value),
    );
  }
}

String _$skyleCurrentControlDataHash() =>
    r'9aec2e8368f65eeb0e066e9a62b19d92665746d0';

/// Stream provider for calibration messages

@ProviderFor(skyleCalibrationStream)
final skyleCalibrationStreamProvider = SkyleCalibrationStreamProvider._();

/// Stream provider for calibration messages

final class SkyleCalibrationStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<CalibrationMessage>,
          CalibrationMessage,
          Stream<CalibrationMessage>
        >
    with
        $FutureModifier<CalibrationMessage>,
        $StreamProvider<CalibrationMessage> {
  /// Stream provider for calibration messages
  SkyleCalibrationStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleCalibrationStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleCalibrationStreamHash();

  @$internal
  @override
  $StreamProviderElement<CalibrationMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<CalibrationMessage> create(Ref ref) {
    return skyleCalibrationStream(ref);
  }
}

String _$skyleCalibrationStreamHash() =>
    r'ff6e2bff0f70a85f0a668cb60c3077d8a4b456c5';

/// Future provider for version info - waits for connection before requesting

@ProviderFor(skyleVersionData)
final skyleVersionDataProvider = SkyleVersionDataProvider._();

/// Future provider for version info - waits for connection before requesting

final class SkyleVersionDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<VersionData>,
          VersionData,
          FutureOr<VersionData>
        >
    with $FutureModifier<VersionData>, $FutureProvider<VersionData> {
  /// Future provider for version info - waits for connection before requesting
  SkyleVersionDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleVersionDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleVersionDataHash();

  @$internal
  @override
  $FutureProviderElement<VersionData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<VersionData> create(Ref ref) {
    return skyleVersionData(ref);
  }
}

String _$skyleVersionDataHash() => r'344a49252f543b7c103266d5cc61b7652663f250';

/// Stream provider for errors

@ProviderFor(skyleErrorStream)
final skyleErrorStreamProvider = SkyleErrorStreamProvider._();

/// Stream provider for errors

final class SkyleErrorStreamProvider
    extends $FunctionalProvider<AsyncValue<String>, String, Stream<String>>
    with $FutureModifier<String>, $StreamProvider<String> {
  /// Stream provider for errors
  SkyleErrorStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleErrorStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleErrorStreamHash();

  @$internal
  @override
  $StreamProviderElement<String> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String> create(Ref ref) {
    return skyleErrorStream(ref);
  }
}

String _$skyleErrorStreamHash() => r'59be728516ecb0597e044a370692212ce734d98c';

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [skyleDeviceLogStreamProvider], which carries firmware log lines.

@ProviderFor(skyleLogStream)
final skyleLogStreamProvider = SkyleLogStreamProvider._();

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [skyleDeviceLogStreamProvider], which carries firmware log lines.

final class SkyleLogStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<SkyleLogMessage>,
          SkyleLogMessage,
          Stream<SkyleLogMessage>
        >
    with $FutureModifier<SkyleLogMessage>, $StreamProvider<SkyleLogMessage> {
  /// Stream provider for diagnostic log messages emitted by the Dart layer
  /// (both the high-level API and the FFI layer). Distinct from
  /// [skyleDeviceLogStreamProvider], which carries firmware log lines.
  SkyleLogStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleLogStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleLogStreamHash();

  @$internal
  @override
  $StreamProviderElement<SkyleLogMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SkyleLogMessage> create(Ref ref) {
    return skyleLogStream(ref);
  }
}

String _$skyleLogStreamHash() => r'd1a047ee6e3eb0b7686e494707891532c1291c6f';

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [SkyleDeviceLogging.enableDeviceLogging] has been turned on.

@ProviderFor(skyleDeviceLogStream)
final skyleDeviceLogStreamProvider = SkyleDeviceLogStreamProvider._();

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [SkyleDeviceLogging.enableDeviceLogging] has been turned on.

final class SkyleDeviceLogStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<SkyleLogMessage>,
          SkyleLogMessage,
          Stream<SkyleLogMessage>
        >
    with $FutureModifier<SkyleLogMessage>, $StreamProvider<SkyleLogMessage> {
  /// Stream provider for firmware log lines (source = `'device'`).
  /// Only emits while [SkyleDeviceLogging.enableDeviceLogging] has been turned on.
  SkyleDeviceLogStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'skyleDeviceLogStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$skyleDeviceLogStreamHash();

  @$internal
  @override
  $StreamProviderElement<SkyleLogMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SkyleLogMessage> create(Ref ref) {
    return skyleDeviceLogStream(ref);
  }
}

String _$skyleDeviceLogStreamHash() =>
    r'05ebe7eafdfa845cc2fa80cb377df37168e5e524';
