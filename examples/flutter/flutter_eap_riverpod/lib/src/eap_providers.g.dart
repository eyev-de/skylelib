// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'eap_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Singleton EAP client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.

@ProviderFor(EapClientInstance)
final eapClientInstanceProvider = EapClientInstanceProvider._();

/// Singleton EAP client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.
final class EapClientInstanceProvider
    extends $NotifierProvider<EapClientInstance, EapClient> {
  /// Singleton EAP client notifier that preserves state across hot restarts.
  /// Uses a static instance to maintain the USB connection through restarts.
  EapClientInstanceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapClientInstanceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapClientInstanceHash();

  @$internal
  @override
  EapClientInstance create() => EapClientInstance();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapClient>(value),
    );
  }
}

String _$eapClientInstanceHash() => r'f97417ceb421a1994961a82d686cd590dafd140a';

/// Singleton EAP client notifier that preserves state across hot restarts.
/// Uses a static instance to maintain the USB connection through restarts.

abstract class _$EapClientInstance extends $Notifier<EapClient> {
  EapClient build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EapClient, EapClient>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EapClient, EapClient>,
              EapClient,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Convenience provider for backwards compatibility

@ProviderFor(eapClient)
final eapClientProvider = EapClientProvider._();

/// Convenience provider for backwards compatibility

final class EapClientProvider
    extends $FunctionalProvider<EapClient, EapClient, EapClient>
    with $Provider<EapClient> {
  /// Convenience provider for backwards compatibility
  EapClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapClientHash();

  @$internal
  @override
  $ProviderElement<EapClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapClient create(Ref ref) {
    return eapClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapClient>(value),
    );
  }
}

String _$eapClientHash() => r'08c44c4eef329d20f60e741d89aced423ed6d999';

@ProviderFor(eapControl)
final eapControlProvider = EapControlProvider._();

final class EapControlProvider
    extends $FunctionalProvider<EapControl, EapControl, EapControl>
    with $Provider<EapControl> {
  EapControlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapControlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapControlHash();

  @$internal
  @override
  $ProviderElement<EapControl> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapControl create(Ref ref) {
    return eapControl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapControl value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapControl>(value),
    );
  }
}

String _$eapControlHash() => r'fb4cdd1e2bb8bf1627b907e404261a13b5f6856c';

@ProviderFor(eapGaze)
final eapGazeProvider = EapGazeProvider._();

final class EapGazeProvider
    extends $FunctionalProvider<EapGaze, EapGaze, EapGaze>
    with $Provider<EapGaze> {
  EapGazeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapGazeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapGazeHash();

  @$internal
  @override
  $ProviderElement<EapGaze> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapGaze create(Ref ref) {
    return eapGaze(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapGaze value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapGaze>(value),
    );
  }
}

String _$eapGazeHash() => r'eb8220c083098ff9634017bb9fa62c8bdbeab7b7';

@ProviderFor(eapPositioning)
final eapPositioningProvider = EapPositioningProvider._();

final class EapPositioningProvider
    extends $FunctionalProvider<EapPositioning, EapPositioning, EapPositioning>
    with $Provider<EapPositioning> {
  EapPositioningProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapPositioningProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapPositioningHash();

  @$internal
  @override
  $ProviderElement<EapPositioning> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapPositioning create(Ref ref) {
    return eapPositioning(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapPositioning value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapPositioning>(value),
    );
  }
}

String _$eapPositioningHash() => r'2c42d1a5587a18a0b0f69c5bbdbc1baada36a712';

@ProviderFor(eapVersion)
final eapVersionProvider = EapVersionProvider._();

final class EapVersionProvider
    extends $FunctionalProvider<EapVersion, EapVersion, EapVersion>
    with $Provider<EapVersion> {
  EapVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapVersionHash();

  @$internal
  @override
  $ProviderElement<EapVersion> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapVersion create(Ref ref) {
    return eapVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapVersion value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapVersion>(value),
    );
  }
}

String _$eapVersionHash() => r'8c653ddf4bf4740c62b5db9f6a41cb02c16a8772';

@ProviderFor(eapCalibration)
final eapCalibrationProvider = EapCalibrationProvider._();

final class EapCalibrationProvider
    extends $FunctionalProvider<EapCalibration, EapCalibration, EapCalibration>
    with $Provider<EapCalibration> {
  EapCalibrationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapCalibrationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapCalibrationHash();

  @$internal
  @override
  $ProviderElement<EapCalibration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapCalibration create(Ref ref) {
    return eapCalibration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapCalibration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapCalibration>(value),
    );
  }
}

String _$eapCalibrationHash() => r'f76548ef969b12b6932e0b7473e36ef456a08eb6';

@ProviderFor(eapDeviceLogging)
final eapDeviceLoggingProvider = EapDeviceLoggingProvider._();

final class EapDeviceLoggingProvider
    extends
        $FunctionalProvider<
          EapDeviceLogging,
          EapDeviceLogging,
          EapDeviceLogging
        >
    with $Provider<EapDeviceLogging> {
  EapDeviceLoggingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapDeviceLoggingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapDeviceLoggingHash();

  @$internal
  @override
  $ProviderElement<EapDeviceLogging> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapDeviceLogging create(Ref ref) {
    return eapDeviceLogging(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapDeviceLogging value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapDeviceLogging>(value),
    );
  }
}

String _$eapDeviceLoggingHash() => r'400ee39e7af8d5bf468a2fd22f957c11d49394ac';

/// Stream provider for gaze data

@ProviderFor(eapGazeDataStream)
final eapGazeDataStreamProvider = EapGazeDataStreamProvider._();

/// Stream provider for gaze data

final class EapGazeDataStreamProvider
    extends
        $FunctionalProvider<AsyncValue<GazesData>, GazesData, Stream<GazesData>>
    with $FutureModifier<GazesData>, $StreamProvider<GazesData> {
  /// Stream provider for gaze data
  EapGazeDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapGazeDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapGazeDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<GazesData> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<GazesData> create(Ref ref) {
    return eapGazeDataStream(ref);
  }
}

String _$eapGazeDataStreamHash() => r'1442a63906202c06203b298b688ab33722808440';

/// Stream provider for positioning data

@ProviderFor(eapPositioningDataStream)
final eapPositioningDataStreamProvider = EapPositioningDataStreamProvider._();

/// Stream provider for positioning data

final class EapPositioningDataStreamProvider
    extends
        $FunctionalProvider<AsyncValue<FaceData>, FaceData, Stream<FaceData>>
    with $FutureModifier<FaceData>, $StreamProvider<FaceData> {
  /// Stream provider for positioning data
  EapPositioningDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapPositioningDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapPositioningDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<FaceData> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<FaceData> create(Ref ref) {
    return eapPositioningDataStream(ref);
  }
}

String _$eapPositioningDataStreamHash() =>
    r'69f1c2ee2600f993d04b451128d1a57a484fa209';

/// Stream provider for video data (raw pixel frames with dimensions)

@ProviderFor(eapVideoDataStream)
final eapVideoDataStreamProvider = EapVideoDataStreamProvider._();

/// Stream provider for video data (raw pixel frames with dimensions)

final class EapVideoDataStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<VideoFrame>,
          VideoFrame,
          Stream<VideoFrame>
        >
    with $FutureModifier<VideoFrame>, $StreamProvider<VideoFrame> {
  /// Stream provider for video data (raw pixel frames with dimensions)
  EapVideoDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapVideoDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapVideoDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<VideoFrame> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<VideoFrame> create(Ref ref) {
    return eapVideoDataStream(ref);
  }
}

String _$eapVideoDataStreamHash() =>
    r'bb8c4a203f0e5bfb2ee27ff112579b58d464e00c';

@ProviderFor(eapVideo)
final eapVideoProvider = EapVideoProvider._();

final class EapVideoProvider
    extends $FunctionalProvider<EapVideo, EapVideo, EapVideo>
    with $Provider<EapVideo> {
  EapVideoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapVideoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapVideoHash();

  @$internal
  @override
  $ProviderElement<EapVideo> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EapVideo create(Ref ref) {
    return eapVideo(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EapVideo value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EapVideo>(value),
    );
  }
}

String _$eapVideoHash() => r'89ac5273094072b13c83ba9558a2f417ded373bf';

/// Stream provider for connection state

@ProviderFor(eapConnectionStateStream)
final eapConnectionStateStreamProvider = EapConnectionStateStreamProvider._();

/// Stream provider for connection state

final class EapConnectionStateStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionState>,
          ConnectionState,
          Stream<ConnectionState>
        >
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
  /// Stream provider for connection state
  EapConnectionStateStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapConnectionStateStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapConnectionStateStreamHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionState> create(Ref ref) {
    return eapConnectionStateStream(ref);
  }
}

String _$eapConnectionStateStreamHash() =>
    r'945b9fb5f62a3095c37b8ec7fad7bfde1e007c4b';

/// Current connection state (from stream)

@ProviderFor(eapConnectionState)
final eapConnectionStateProvider = EapConnectionStateProvider._();

/// Current connection state (from stream)

final class EapConnectionStateProvider
    extends
        $FunctionalProvider<ConnectionState, ConnectionState, ConnectionState>
    with $Provider<ConnectionState> {
  /// Current connection state (from stream)
  EapConnectionStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapConnectionStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapConnectionStateHash();

  @$internal
  @override
  $ProviderElement<ConnectionState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConnectionState create(Ref ref) {
    return eapConnectionState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionState>(value),
    );
  }
}

String _$eapConnectionStateHash() =>
    r'a05a42c1a25cc9d96d8607f50498f3b1bba0e1bd';

/// Stream provider for control data

@ProviderFor(eapControlDataStream)
final eapControlDataStreamProvider = EapControlDataStreamProvider._();

/// Stream provider for control data

final class EapControlDataStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<ControlData>,
          ControlData,
          Stream<ControlData>
        >
    with $FutureModifier<ControlData>, $StreamProvider<ControlData> {
  /// Stream provider for control data
  EapControlDataStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapControlDataStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapControlDataStreamHash();

  @$internal
  @override
  $StreamProviderElement<ControlData> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ControlData> create(Ref ref) {
    return eapControlDataStream(ref);
  }
}

String _$eapControlDataStreamHash() =>
    r'9002f7d9e550ff9d2fcac6b6d9345e750ed2328c';

/// Current control data

@ProviderFor(eapCurrentControlData)
final eapCurrentControlDataProvider = EapCurrentControlDataProvider._();

/// Current control data

final class EapCurrentControlDataProvider
    extends $FunctionalProvider<ControlData, ControlData, ControlData>
    with $Provider<ControlData> {
  /// Current control data
  EapCurrentControlDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapCurrentControlDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapCurrentControlDataHash();

  @$internal
  @override
  $ProviderElement<ControlData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ControlData create(Ref ref) {
    return eapCurrentControlData(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlData>(value),
    );
  }
}

String _$eapCurrentControlDataHash() =>
    r'390fe44d7458685c2962cfc784eb07bdc483d730';

/// Stream provider for calibration messages

@ProviderFor(eapCalibrationStream)
final eapCalibrationStreamProvider = EapCalibrationStreamProvider._();

/// Stream provider for calibration messages

final class EapCalibrationStreamProvider
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
  EapCalibrationStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapCalibrationStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapCalibrationStreamHash();

  @$internal
  @override
  $StreamProviderElement<CalibrationMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<CalibrationMessage> create(Ref ref) {
    return eapCalibrationStream(ref);
  }
}

String _$eapCalibrationStreamHash() =>
    r'91ec3631458ae032bdf782883f0eb5a9e174bbc0';

/// Future provider for version info - waits for connection before requesting

@ProviderFor(eapVersionData)
final eapVersionDataProvider = EapVersionDataProvider._();

/// Future provider for version info - waits for connection before requesting

final class EapVersionDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<VersionData>,
          VersionData,
          FutureOr<VersionData>
        >
    with $FutureModifier<VersionData>, $FutureProvider<VersionData> {
  /// Future provider for version info - waits for connection before requesting
  EapVersionDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapVersionDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapVersionDataHash();

  @$internal
  @override
  $FutureProviderElement<VersionData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<VersionData> create(Ref ref) {
    return eapVersionData(ref);
  }
}

String _$eapVersionDataHash() => r'ca8ee4b9d616673383c1644a670141b7faf3433d';

/// Stream provider for errors

@ProviderFor(eapErrorStream)
final eapErrorStreamProvider = EapErrorStreamProvider._();

/// Stream provider for errors

final class EapErrorStreamProvider
    extends $FunctionalProvider<AsyncValue<String>, String, Stream<String>>
    with $FutureModifier<String>, $StreamProvider<String> {
  /// Stream provider for errors
  EapErrorStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapErrorStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapErrorStreamHash();

  @$internal
  @override
  $StreamProviderElement<String> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String> create(Ref ref) {
    return eapErrorStream(ref);
  }
}

String _$eapErrorStreamHash() => r'7ed2b5cb7d59b3c6abcd21bd429606fb36647e60';

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [eapDeviceLogStreamProvider], which carries firmware log lines.

@ProviderFor(eapLogStream)
final eapLogStreamProvider = EapLogStreamProvider._();

/// Stream provider for diagnostic log messages emitted by the Dart layer
/// (both the high-level API and the FFI layer). Distinct from
/// [eapDeviceLogStreamProvider], which carries firmware log lines.

final class EapLogStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<EapLogMessage>,
          EapLogMessage,
          Stream<EapLogMessage>
        >
    with $FutureModifier<EapLogMessage>, $StreamProvider<EapLogMessage> {
  /// Stream provider for diagnostic log messages emitted by the Dart layer
  /// (both the high-level API and the FFI layer). Distinct from
  /// [eapDeviceLogStreamProvider], which carries firmware log lines.
  EapLogStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapLogStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapLogStreamHash();

  @$internal
  @override
  $StreamProviderElement<EapLogMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<EapLogMessage> create(Ref ref) {
    return eapLogStream(ref);
  }
}

String _$eapLogStreamHash() => r'f2e93d2bef7fac978dfa63e5bce4b67e937d1ca0';

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [EapDeviceLogging.enableDeviceLogging] has been turned on.

@ProviderFor(eapDeviceLogStream)
final eapDeviceLogStreamProvider = EapDeviceLogStreamProvider._();

/// Stream provider for firmware log lines (source = `'device'`).
/// Only emits while [EapDeviceLogging.enableDeviceLogging] has been turned on.

final class EapDeviceLogStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<EapLogMessage>,
          EapLogMessage,
          Stream<EapLogMessage>
        >
    with $FutureModifier<EapLogMessage>, $StreamProvider<EapLogMessage> {
  /// Stream provider for firmware log lines (source = `'device'`).
  /// Only emits while [EapDeviceLogging.enableDeviceLogging] has been turned on.
  EapDeviceLogStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eapDeviceLogStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eapDeviceLogStreamHash();

  @$internal
  @override
  $StreamProviderElement<EapLogMessage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<EapLogMessage> create(Ref ref) {
    return eapDeviceLogStream(ref);
  }
}

String _$eapDeviceLogStreamHash() =>
    r'd842b7c568545e25a0ccab28351247dcc9601676';
