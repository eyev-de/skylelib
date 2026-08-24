/// High-level Skyle client API for eye tracking
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi/skyle_client_ffi.dart';
import 'models/models.dart';

abstract class SkyleGaze {
  Stream<GazesData> get gazeDataStream;
  Future<void> enableGaze(bool enable);
}

abstract class SkylePositioning {
  Stream<FaceData> get positioningDataStream;
  Future<void> enablePositioning(bool enable);
}

abstract class SkyleVersion {
  Future<VersionData> requestVersion();
}

abstract class SkyleCalibration {
  Stream<CalibrationMessage> get calibrationStream;
  Future<void> startCalibration(CalibrationConfig config);
  Future<void> collectCalibrationPoints();
  Future<void> abortCalibration();
}

abstract class SkyleVideo {
  Stream<VideoFrame> get videoDataStream;
  Future<void> enableVideo(bool enable);
}

abstract class SkyleFileUpload {
  Stream<FileUploadStatus> get fileStatusStream;
  Stream<FileUploadProgress> uploadFile(Uint8List fileData, String devicePath);
  void cancelUpload();
}

abstract class SkyleDeviceLogging {
  /// Log lines streamed from the firmware (only delivered while logging
  /// has been enabled via [enableDeviceLogging]).
  Stream<SkyleLogMessage> get deviceLogStream;
  Future<void> enableDeviceLogging(bool enable);
}

abstract class SkyleControl {
  Stream<ControlData> get controlDataStream;
  Future<void> enableControl(bool enable);
  Future<void> sendControl(ControlMessage message);

  /// Send the client's display info (resolution in px, physical size in mm)
  /// to the device. Fire-and-forget; safe to call even if not yet connected —
  /// the value is cached and resent automatically once the link is ready.
  Future<void> sendDisplayInfo(DisplayInfo info);

  /// Most recently set display info (may not yet have been sent).
  DisplayInfo? get displayInfo;

  ControlData get controlData;

  bool get isStandbyEnabled;
  bool get isAutoPauseEnabled;
  bool get isPauseEnabled;
  TrackingMode get trackingMode;
  int get gazeFilter;
  int get fixationFilter;
  bool get isAssistiveTouchEnabled;
  bool get showTrackingDetails;
  bool get isHidEnabled;
  bool get isEthernetEnabled;

  set isStandbyEnabled(bool value);
  set isAutoPauseEnabled(bool value);
  set isPauseEnabled(bool value);
  set trackingMode(TrackingMode value);
  set gazeFilter(int value);
  set fixationFilter(int value);
  set isAssistiveTouchEnabled(bool value);
  set showTrackingDetails(bool value);
  set isHidEnabled(bool value);
  set isEthernetEnabled(bool value);

  set isAssistiveTouchAndHidEnabled(bool value);

  void defaultFilter();
}

/// Runs hash + native malloc+memcpy in a background isolate.
/// Must be top-level (not a closure or method) for [compute].
(int, Uint8List) _prepareUploadData(Uint8List fileData) {
  final hash = sha256.convert(fileData);
  final nativeData = malloc<Uint8>(fileData.length);
  if (nativeData == nullptr) return (0, Uint8List(0));
  nativeData.asTypedList(fileData.length).setAll(0, fileData);
  return (nativeData.address, Uint8List.fromList(hash.bytes));
}

/// High-level Skyle client for eye tracking device communication
///
/// Usage:
/// ```dart
/// final client = SkyleClient();
/// await client.initialize();
/// await client.connect();
///
/// // Listen to gaze data
/// client.gazeStream.listen((gaze) {
///   print('Gaze: ${gaze.gazeX}, ${gaze.gazeY}');
/// });
///
/// // Enable gaze streaming
/// await client.enableGaze(true);
/// ```
class SkyleClient implements SkyleControl, SkyleGaze, SkylePositioning, SkyleVideo, SkyleVersion, SkyleCalibration, SkyleFileUpload, SkyleDeviceLogging {
  final SkyleClientFfi _ffi = SkyleClientFfi();
  bool _initialized = false;
  DisplayInfo? _displayInfo;
  StreamSubscription<ConnectionState>? _stateSub;
  StreamSubscription<ControlData>? _controlIngestSub;
  final StreamController<ControlData> _controlDataController = StreamController<ControlData>.broadcast();

  // True once the device has pushed a control message in the current link
  // session. Reset when the link drops so we never echo stale cached values
  // back to the device on reconnect (which would overwrite its persisted
  // state — the very bug this gate exists to prevent).
  bool _hasReceivedControl = false;

  // Writes issued before the device has pushed its current state are stored
  // here as field-level deltas (functions applied via ControlData.copyWith).
  // On the next ingest we fold them onto the device-fresh ControlData, emit
  // the merged view, and send one coalesced sendControl back. This preserves
  // user intent across reconnect races without risking the ControlData.empty()
  // clobber described above. Later writes to the same field supersede earlier
  // ones by insertion order.
  final List<ControlData Function(ControlData)> _pendingDeltas = [];

  // ==========================================================================
  // Public Streams
  // ==========================================================================

  /// Stream of gaze data (60 Hz when enabled)
  @override
  Stream<GazesData> get gazeDataStream => _ffi.gazeDataStream;

  /// Stream of positioning data (60 Hz when enabled)
  @override
  Stream<FaceData> get positioningDataStream => _ffi.positioningDataStream;

  /// Stream of video frames (raw JPEG/MJPEG data)
  @override
  Stream<VideoFrame> get videoDataStream => _ffi.videoDataStream;

  /// Stream of control state updates
  @override
  Stream<ControlData> get controlDataStream => _controlDataController.stream;

  /// Unified stream of calibration messages
  @override
  Stream<CalibrationMessage> get calibrationStream => _ffi.calibrationStream;

  /// Stream of file transfer status messages from the device
  @override
  Stream<FileUploadStatus> get fileStatusStream => _ffi.fileStatusStream;

  /// Stream of connection state changes
  Stream<ConnectionState> get stateStream => _ffi.stateStream;

  /// Current connection state read synchronously from the native client.
  /// Use to seed new listeners: [stateStream] only carries transitions, so a
  /// listener created after the link came up would otherwise never see a value.
  ConnectionState get currentState => _ffi.currentState;

  /// Stream of error messages
  Stream<String> get errorStream => _ffi.errorStream;

  /// Stream of diagnostic log messages emitted by the client (both the
  /// high-level API and the FFI layer). Useful for surfacing internal state
  /// transitions in an in-app log console.
  Stream<SkyleLogMessage> get logStream => _ffi.logStream;

  /// Log lines streamed from the firmware itself (source = `'device'`).
  /// Only delivered while [enableDeviceLogging] has been turned on.
  @override
  Stream<SkyleLogMessage> get deviceLogStream => _ffi.deviceLogStream;

  /// Skyle Link eye-control suspension changes (broadcast). Emits whenever a
  /// client takes or releases the suspension lease (or its connection dies).
  /// Sources per mode: hub owner - the hub's SUSPEND_CHANGED events;
  /// local-link client - the skyle_link suspend callback. On every fan-out
  /// platform (Android, macOS, Windows, Linux) the native layer fans both out
  /// to each engine's subscriber slot. Seed new listeners from
  /// [currentSuspensionState]; this stream only carries changes.
  Stream<SkyleLinkSuspendState> get suspensionStream => _ffi.suspensionStream;

  /// Current Skyle Link suspension state, read from the native cached state.
  /// Not suspended when Skyle Link is unused or unsupported.
  SkyleLinkSuspendState get currentSuspensionState => _ffi.currentSuspensionState;

  /// Skyle Link HOST_CONTROL commands received while this process serves the
  /// hub (broadcast). Only the hub owner receives them - a local-link client
  /// sends via [sendHostControl] instead. Commands, not state: there is no
  /// seed, nothing is cached, and the last writer wins at the receiver.
  Stream<SkyleLinkHostControl> get hostControlStream => _ffi.hostControlStream;

  /// Skyle Link hub client presence changes (broadcast). Only the hub owner
  /// receives them; the disconnect events carry the app id a
  /// restore-on-disconnect policy keys on. Events, not state - no seed.
  Stream<SkyleLinkClientEvent> get linkClientStream => _ffi.linkClientStream;

  void _log(LogLevel level, String message) {
    _ffi.emitLog(level, 'SkyleClient', message);
  }

  // ==========================================================================
  // Lifecycle
  // ==========================================================================

  /// Skyle Link identity used when [initialize] is called without an explicit
  /// `identity` (e.g. by the flutter_skyle_riverpod providers). Set it BEFORE
  /// the first initialize - typically early in main(). Only consulted on
  /// desktop (see [initialize]); null means the native defaults apply
  /// (third-party app id, default tier).
  static SkyleLinkIdentity? defaultIdentity;

  /// Initialize the client (call once at app startup).
  ///
  /// Transport selection (direct USB vs Skyle Link socket) is fully automatic:
  /// the native supervisor elects the hub owner among local apps, dials as a
  /// client otherwise, and swaps a running session live on handovers - the
  /// application only observes a DISCONNECTED -> LINK_SYNCED blip.
  ///
  /// [identity] is this app's Skyle Link identity (HELLO app id + priority
  /// tier). Resolution order: an explicit [identity] wins, else
  /// [defaultIdentity], else null (native defaults - third-party app id,
  /// default tier). Platform behavior:
  /// - Desktop (macOS/Windows/Linux): the resolved identity is published and
  ///   the supervisor is enabled.
  /// - Android: ignored - the Kotlin layer owns identity and supervisor
  ///   (SkyleUsbHost publishes skylex; SDK apps use manifest meta-data).
  /// - iOS: ignored - the supervisor is disabled there.
  void initialize({SkyleLinkIdentity? identity}) {
    if (_initialized) {
      return;
    }

    // Initialize FFI bindings
    SkyleClientFfi.initializeBindings();

    // Create native client
    _ffi.create();

    // Skyle Link automatic transport supervisor (desktop only - Android's
    // platform layer owns it, and a late Dart set_identity would clobber the
    // service-published skylex identity; iOS runs without a supervisor).
    // Runs once per engine under the subscriber fan-out: enable is idempotent,
    // and a sub-window engine initializing with a null identity skips
    // set_identity entirely, so it can never clobber the identity published
    // by the engine that supplied one.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _ffi.configureLinkSupervisor(identity ?? defaultIdentity);
    }

    // Single ingest path for device control messages. Updates the cached
    // `_controlData`, marks the link as having received state, flushes any
    // deltas queued while gated, and forwards to the public broadcast stream.
    // Done here (not in the getter) so every control message is observed
    // exactly once regardless of how many subscribers the getter has.
    _controlIngestSub = _ffi.controlDataStream.listen((event) {
      final hadPending = _pendingDeltas.isNotEmpty;
      _log(
        LogLevel.information,
        'control stream: ingest at=${event.isAssistiveTouchEnabled} hid=${event.isHidEnabled} '
        'pause=${event.isPauseEnabled} mode=${event.trackingMode} pending=${_pendingDeltas.length} '
        'firstAfterReady=${!_hasReceivedControl}',
      );
      var effective = event;
      if (hadPending) {
        for (final delta in _pendingDeltas) {
          effective = delta(effective);
        }
        _pendingDeltas.clear();
        _log(
          LogLevel.information,
          'control stream: applied pending deltas -> at=${effective.isAssistiveTouchEnabled} '
          'hid=${effective.isHidEnabled}',
        );
      }

      _controlData = effective;
      _hasReceivedControl = true;
      _controlDataController.add(effective);

      // If the user (or a side-effect) issued writes while we were gated,
      // push the merged result back to the device. The device will echo its
      // now-updated state, which flows through this same listener.
      if (hadPending) {
        _log(LogLevel.information, 'control stream: sending merged state back to device');
        sendControl(effective);
      }
    });

    // Resend cached display info every time the link becomes ready so the
    // device always has the latest client display dimensions after connect
    // / reconnect / hot restart. Also drop the control-seen flag when the
    // link is not ready so we wait for the device to push its persisted
    // state again before accepting any setter writes.
    _stateSub = _ffi.stateStream.listen((state) {
      if (!state.isReady) {
        _hasReceivedControl = false;
      }
      if (state.isReady && _displayInfo != null) {
        try {
          _ffi.sendDisplayInfo(_displayInfo!);
        } catch (e) {
          _log(LogLevel.error, 'auto-send display info failed: $e');
        }
      }
    });

    _initialized = true;
  }

  /// Dispose the client and cleanup resources
  Future<void> dispose() async {
    if (!_initialized) return;

    try {
      // Fan-out engines share the process-wide native client, so an engine's
      // teardown must not stop the shared transport (destroy() below removes
      // only this engine's subscriber). Android keeps the call for plugin-only
      // runs; while the transport is host-owned the native layer no-ops it.
      if (Platform.isAndroid || !_ffi.sharesNativeClient) await disconnect();
    } catch (_) {}

    await _stateSub?.cancel();
    _stateSub = null;

    await _controlIngestSub?.cancel();
    _controlIngestSub = null;
    _pendingDeltas.clear();
    await _controlDataController.close();

    _ffi.destroy();
    _initialized = false;
  }

  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('Client not initialized - call initialize() first');
    }
  }

  // ==========================================================================
  // Connection Control
  // ==========================================================================

  /// Connect to the device and start background thread
  Future<void> connect() async {
    _checkInitialized();

    // While the Skyle Link supervisor runs a local link (socket to another
    // process's hub), the USB connect path would replace that transport.
    if (_ffi.isLocalLink) {
      _log(LogLevel.debug, 'connect() skipped - local Skyle Link transport is active');
      return;
    }

    _log(LogLevel.information, 'Starting connect...');

    _log(LogLevel.debug, 'Calling FFI connect...');
    final result = _ffi.connect();
    _log(LogLevel.debug, 'FFI connect result: $result');
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Connect failed: $error (code: $result)');
    }
    _log(LogLevel.information, 'Connect complete');
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    _checkInitialized();

    final result = _ffi.disconnect();
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Disconnect failed: $error (code: $result)');
    }
  }

  /// Get current connection state
  ConnectionState get state {
    _checkInitialized();
    return _ffi.getState();
  }

  /// True if ready to send/receive messages (LinkSynced state)
  bool get isReady => state.isReady;

  /// True if connected (any state except disconnected/error)
  bool get isConnected => state.isConnected;

  // ==========================================================================
  // Skyle Link (multi-app sharing)
  // ==========================================================================

  /// Request ([suspended] = true) or release (false) the eye-control
  /// suspension lease. Local-link client mode only: returns false and does
  /// nothing when this process is the hub owner or not in local mode (the
  /// hub-hosting app suspends by reacting to [suspensionStream], not by
  /// leasing from itself). The result of the request arrives as a
  /// SUSPEND_STATE broadcast on [suspensionStream].
  Future<bool> setEyeControlSuspended(bool suspended) async {
    if (!_initialized) {
      return false;
    }
    if (_ffi.isHubOwner) {
      _log(LogLevel.warning, 'setEyeControlSuspended ignored - this process is the hub owner');
      return false;
    }
    if (!_ffi.isLocalLink) {
      _log(LogLevel.warning, 'setEyeControlSuspended ignored - not in local-link mode');
      return false;
    }
    final result = _ffi.setLinkSuspended(suspended);
    if (result != 0) {
      _log(LogLevel.warning, 'setEyeControlSuspended($suspended) failed (code $result)');
    }
    return result == 0;
  }

  /// Send a fire-and-forget HOST_CONTROL command to the app hosting the hub
  /// (Skyle X). Local-link client mode only: returns false and does nothing
  /// when this process is the hub owner or not in local mode. No reply, no
  /// lease - unknown control ids are ignored by the receiver and the last
  /// writer wins. [value] layout is per control id (see
  /// [SkyleLinkHostControlId]); the typed helpers below cover the well-known
  /// ids.
  Future<bool> sendHostControl(int controlId, [Uint8List? value]) async {
    if (!_initialized) {
      return false;
    }
    if (_ffi.isHubOwner) {
      _log(LogLevel.warning, 'sendHostControl ignored - this process is the hub owner');
      return false;
    }
    if (!_ffi.isLocalLink) {
      _log(LogLevel.warning, 'sendHostControl ignored - not in local-link mode');
      return false;
    }
    final result = _ffi.sendHostControl(controlId, value ?? Uint8List(0));
    if (result != 0) {
      _log(LogLevel.warning, 'sendHostControl($controlId) failed (code $result)');
    }
    return result == 0;
  }

  /// Show or completely hide the hub-hosting app's menu bar (hiding also
  /// disables its pause edge). The host restores a hidden menu bar when this
  /// app disconnects.
  Future<bool> setHostMenuBarVisible(bool visible) => sendHostControl(SkyleLinkHostControlId.menuBar, Uint8List.fromList([visible ? 1 : 0]));

  /// Show or hide the hub-hosting app's pointer overlay (hiding also disables
  /// snap-to-item and the left/right edges). The host restores a hidden
  /// overlay when this app disconnects.
  Future<bool> setHostPointerVisible(bool visible) => sendHostControl(SkyleLinkHostControlId.pointerOverlay, Uint8List.fromList([visible ? 1 : 0]));

  /// Bring the hub-hosting app to the foreground and start a calibration.
  /// [points] 0 sends no value byte (the host's default point count applies),
  /// otherwise pass a point count the host supports (5 or 9).
  Future<bool> startHostCalibration({int points = 0}) =>
      sendHostControl(SkyleLinkHostControlId.startCalibration, points > 0 ? Uint8List.fromList([points]) : null);

  /// Stop the Android process-wide USB host (SkyleUsbHost.stop()): disables the
  /// Skyle Link supervisor (BYE(handover) to hub clients), releases the USB
  /// device, and clears native host ownership so another app can take over
  /// the tracker. No-op on all other platforms.
  static Future<void> stopUsbHost() => SkyleClientFfi.stopUsbHost();

  // ==========================================================================
  // Feature Control
  // ==========================================================================

  /// Enable or disable gaze streaming
  ///
  /// When enabled, [gazeStream] will emit data at 30-60 Hz
  @override
  Future<void> enableGaze(bool enable) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.enableGaze(enable);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Enable gaze failed: $error (code: $result)');
    }
  }

  /// Enable or disable video streaming
  @override
  Future<void> enableVideo(bool enable) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.enableVideo(enable);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Enable video failed: $error (code: $result)');
    }
  }

  /// Enable or disable streaming of firmware log lines.
  ///
  /// When enabled, the device pushes its `ILogger`-emitted lines to
  /// [deviceLogStream] (severity Information and above, ~511-byte UTF-8 max).
  @override
  Future<void> enableDeviceLogging(bool enable) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.enableLogging(enable);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Enable device logging failed: $error (code: $result)');
    }
  }

  /// Enable or disable positioning streaming
  ///
  /// When enabled, [positioningStream] will emit data at 30 Hz
  @override
  Future<void> enablePositioning(bool enable) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.enablePositioning(enable);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Enable positioning failed: $error (code: $result)');
    }
  }

  /// Request device version string
  ///
  /// Result will be emitted on [versionStream]
  @override
  Future<VersionData> requestVersion() {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return Future.value(
        VersionData(firmware: '', serial: BigInt.zero, isDemoDevice: false, deviceType: 0, devicePlatform: 0, deviceGeneration: 0, protocolVersion: ''),
      );
    }

    return _ffi.requestVersion();
  }

  /// Request control state
  ///
  /// When enabled, [controlStream] will emit control data
  @override
  Future<void> enableControl(bool enable) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.enableControl(enable);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Enable control stream failed: $error (code: $result)');
    }
  }

  @override
  Future<void> sendControl(ControlMessage message) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages (isConnected=$isConnected, state=$state)');
      return;
    }

    final result = _ffi.sendControl(message);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Send control request failed: $error (code: $result)');
    }
  }

  @override
  DisplayInfo? get displayInfo => _displayInfo;

  @override
  Future<void> sendDisplayInfo(DisplayInfo info) async {
    _checkInitialized();
    // Cache so we can auto-resend on (re)connect.
    _displayInfo = info;

    if (!isReady) {
      // Will be sent by the stateStream listener once the link is ready.
      return;
    }

    final result = _ffi.sendDisplayInfo(info);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Send display info failed: $error (code: $result)');
    }
  }

  ControlData _controlData = ControlData.empty();

  @override
  ControlData get controlData => _controlData;

  @override
  bool get isStandbyEnabled => _controlData.isStandbyEnabled;

  @override
  bool get isAutoPauseEnabled => _controlData.isAutoPauseEnabled;

  @override
  bool get isPauseEnabled => _controlData.isPauseEnabled;

  @override
  TrackingMode get trackingMode => _controlData.trackingMode;

  @override
  int get gazeFilter => _controlData.gazeFilter;

  @override
  int get fixationFilter => _controlData.fixationFilter;

  @override
  bool get isAssistiveTouchEnabled => _controlData.isAssistiveTouchEnabled;

  @override
  bool get showTrackingDetails => _controlData.showTrackingDetails;

  @override
  bool get isHidEnabled => _controlData.isHidEnabled;

  @override
  bool get isEthernetEnabled => _controlData.isEthernetEnabled;

  // All setters funnel through _write, which either sends immediately (when
  // the device has already pushed its current state) or queues the delta for
  // the next ingest to fold onto a device-fresh ControlData. This prevents
  // the ControlData.empty() clobber: a write queued before first ingest never
  // becomes a full message built on top of the empty default.
  void _write(ControlData Function(ControlData) delta) {
    if (_hasReceivedControl) {
      _controlData = delta(_controlData);
      _log(
        LogLevel.information,
        'control write: send immediate at=${_controlData.isAssistiveTouchEnabled} '
        'hid=${_controlData.isHidEnabled} pause=${_controlData.isPauseEnabled} mode=${_controlData.trackingMode}',
      );
      sendControl(_controlData);
    } else {
      _pendingDeltas.add(delta);
      _log(
        LogLevel.information,
        'control write: queued delta (no device state yet) pendingCount=${_pendingDeltas.length}',
      );
    }
  }

  @override
  set isStandbyEnabled(bool value) => _write((c) => c.copyWith(isStandbyEnabled: value));

  @override
  set isAutoPauseEnabled(bool value) => _write((c) => c.copyWith(isAutoPauseEnabled: value));

  @override
  set isPauseEnabled(bool value) => _write((c) => c.copyWith(isPauseEnabled: value));

  @override
  set trackingMode(TrackingMode value) => _write((c) => c.copyWith(trackingMode: value));

  @override
  set gazeFilter(int value) => _write((c) => c.copyWith(gazeFilter: value));

  @override
  set fixationFilter(int value) => _write((c) => c.copyWith(fixationFilter: value));

  @override
  set isAssistiveTouchEnabled(bool value) => _write((c) => c.copyWith(isAssistiveTouchEnabled: value));

  @override
  set showTrackingDetails(bool value) => _write((c) => c.copyWith(showTrackingDetails: value));

  @override
  set isHidEnabled(bool value) => _write((c) => c.copyWith(isHidEnabled: value));

  @override
  set isEthernetEnabled(bool value) => _write((c) => c.copyWith(isEthernetEnabled: value));

  @override
  set isAssistiveTouchAndHidEnabled(bool value) => _write((c) => c.copyWith(isAssistiveTouchEnabled: value, isHidEnabled: value));

  @override
  void defaultFilter() => _write((c) => c.copyWith(gazeFilter: 5, fixationFilter: 30));

  // ==========================================================================
  // File Upload
  // ==========================================================================

  /// Upload a file to the device.
  ///
  /// Chunking, size validation, and the StartFile/FileData/EndFile sequence
  /// are all handled by the C library. Dart only needs to pass the raw bytes,
  /// compute the SHA-256 hash, and wait for the device's final status.
  ///
  /// [fileData] - Raw file bytes to upload.
  /// [devicePath] - Destination path on the device.
  ///
  /// Returns a stream of [FileUploadProgress] events.
  /// Listen to the stream to track progress; it completes when the device
  /// reports success or failure (or after a timeout scaled to file size).
  @override
  Stream<FileUploadProgress> uploadFile(Uint8List fileData, String devicePath) async* {
    _checkInitialized();
    if (!isReady) {
      throw SkyleException('Not connected to device');
    }

    // Offload hash computation + native memory copy to a background isolate
    // so the UI thread doesn't freeze for large files (500MB+ = ~300-500ms).
    // malloc uses the system allocator, so the pointer is valid across isolates.
    final prepared = await compute(_prepareUploadData, fileData);

    final (dataAddress, hashBytes) = prepared;
    if (dataAddress == 0) {
      throw SkyleException('Failed to allocate native memory for file data');
    }

    // Trivial main-thread work: pass the pointer to native (instant FFI call)
    final nativeData = Pointer<Uint8>.fromAddress(dataAddress);
    final nativeHash = calloc<Uint8>(32);
    if (nativeHash == nullptr) {
      malloc.free(nativeData);
      throw SkyleException('Failed to allocate memory for hash');
    }
    try {
      nativeHash.asTypedList(32).setAll(0, hashBytes);
      final result = _ffi.uploadFile(nativeData, fileData.length, devicePath, nativeHash);
      if (result != 0) {
        // Native did NOT take ownership — free here
        malloc.free(nativeData);
        throw SkyleException('File upload start failed (code: $result)');
      }
      // Native took ownership of nativeData — do NOT free it
    } finally {
      calloc.free(nativeHash);
    }

    // Scale timeout with file size: 3min base + 5s per MB
    final fileMb = (fileData.length / (1024 * 1024)).ceil();
    final timeoutDuration = Duration(seconds: 180 + fileMb * 5);

    // Wrap the broadcast fileStatusStream in a local single-subscription
    // controller so the timer can inject a synthetic FAILED event and close
    // the stream even after the upload thread has already exited (in which
    // case cancelUpload() is a no-op and the broadcast stream stays open).
    final localController = StreamController<FileUploadStatus>();
    final sub = fileStatusStream.listen(
      (status) {
        if (!localController.isClosed) localController.add(status);
      },
      onError: (Object e, StackTrace st) {
        if (!localController.isClosed) localController.addError(e, st);
      },
      cancelOnError: false,
    );

    bool timedOut = false;
    final timeout = Timer(timeoutDuration, () {
      timedOut = true;
      _ffi.cancelUpload(); // cancels upload thread if still running
      // Force-close the local stream so the await-for exits even if the
      // upload thread has already finished and no more events are coming.
      if (!localController.isClosed) {
        localController.add(FileUploadStatus(status: FileTransferStatus.failed, errorMessage: 'Upload timed out (${timeoutDuration.inSeconds}s)'));
        localController.close();
      }
    });

    try {
      await for (final status in localController.stream) {
        yield FileUploadProgress(
          bytesSent: status.isProgress ? (fileData.length * status.progress / 100).round() : fileData.length,
          totalBytes: fileData.length,
          chunksSent: 0,
          totalChunks: 0,
          deviceProgress: status.progress,
          deviceStatus: status.status,
          errorMessage: status.errorMessage,
        );

        if (status.isSuccess) {
          return;
        }

        if (status.isFailed) {
          if (timedOut) {
            throw SkyleException('Upload timed out waiting for device confirmation');
          }
          throw SkyleException('Upload failed: ${status.errorMessage}');
        }
      }
    } finally {
      timeout.cancel();
      await sub.cancel();
      if (!localController.isClosed) await localController.close();
    }
  }

  @override
  void cancelUpload() {
    _checkInitialized();
    _ffi.cancelUpload();
  }

  // ==========================================================================
  // Calibration Control
  // ==========================================================================

  /// Start calibration process
  ///
  /// [config] - Calibration configuration (point count, screen dimensions)
  ///
  /// Listen to [calibrationStream] for:
  /// - [NextCalibrationPointMessage] - points to display
  /// - [ProgressCalibrationPointMessage] - collection progress (0-100%)
  /// - [PausedCalibrationMessage] - calibration paused
  /// - [FinishedCalibrationMessage] - calibration complete with results
  ///
  /// Call [nextCalibrationPoint] when user is ready for each point
  @override
  Future<void> startCalibration(CalibrationConfig config) async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.startCalibration(config);
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Start calibration failed: $error (code: $result)');
    }
  }

  /// Signal ready for next calibration point
  ///
  /// Call this after displaying the calibration point to the user
  @override
  Future<void> collectCalibrationPoints() async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.collectCalibrationPoints();
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Collect calibration points failed: $error (code: $result)');
    }
  }

  /// Abort calibration process
  @override
  Future<void> abortCalibration() async {
    _checkInitialized();
    if (!isReady) {
      _log(LogLevel.warning, 'Not ready to send/receive messages');
      return;
    }

    final result = _ffi.abortCalibration();
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw SkyleException('Abort calibration failed: $error (code: $result)');
    }
  }
}

/// Exception thrown by SkyleClient operations
class SkyleException implements Exception {
  final String message;

  SkyleException(this.message);

  @override
  String toString() => 'SkyleException: $message';
}
