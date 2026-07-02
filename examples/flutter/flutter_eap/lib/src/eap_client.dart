/// High-level EAP client API for eye tracking
library;

import 'dart:async';
import 'dart:ffi';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi/eap_client_ffi.dart';
import 'models/models.dart';

abstract class EapGaze {
  Stream<GazesData> get gazeDataStream;
  Future<void> enableGaze(bool enable);
}

abstract class EapPositioning {
  Stream<FaceData> get positioningDataStream;
  Future<void> enablePositioning(bool enable);
}

abstract class EapVersion {
  Future<VersionData> requestVersion();
}

abstract class EapCalibration {
  Stream<CalibrationMessage> get calibrationStream;
  Future<void> startCalibration(CalibrationConfig config);
  Future<void> collectCalibrationPoints();
  Future<void> abortCalibration();
}

abstract class EapVideo {
  Stream<VideoFrame> get videoDataStream;
  Future<void> enableVideo(bool enable);
}

abstract class EapFileUpload {
  Stream<FileUploadStatus> get fileStatusStream;
  Stream<FileUploadProgress> uploadFile(Uint8List fileData, String devicePath);
  void cancelUpload();
}

abstract class EapDeviceLogging {
  /// Log lines streamed from the firmware (only delivered while logging
  /// has been enabled via [enableDeviceLogging]).
  Stream<EapLogMessage> get deviceLogStream;
  Future<void> enableDeviceLogging(bool enable);
}

abstract class EapControl {
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

/// High-level EAP client for eye tracking device communication
///
/// Usage:
/// ```dart
/// final client = EapClient();
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
class EapClient implements EapControl, EapGaze, EapPositioning, EapVideo, EapVersion, EapCalibration, EapFileUpload, EapDeviceLogging {
  final EapClientFfi _ffi = EapClientFfi();
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

  /// Stream of error messages
  Stream<String> get errorStream => _ffi.errorStream;

  /// Stream of diagnostic log messages emitted by the client (both the
  /// high-level API and the FFI layer). Useful for surfacing internal state
  /// transitions in an in-app log console.
  Stream<EapLogMessage> get logStream => _ffi.logStream;

  /// Log lines streamed from the firmware itself (source = `'device'`).
  /// Only delivered while [enableDeviceLogging] has been turned on.
  @override
  Stream<EapLogMessage> get deviceLogStream => _ffi.deviceLogStream;

  void _log(LogLevel level, String message) {
    _ffi.emitLog(level, 'EapClient', message);
  }

  // ==========================================================================
  // Lifecycle
  // ==========================================================================

  /// Initialize the client (call once at app startup)
  void initialize() {
    if (_initialized) {
      return;
    }

    // Initialize FFI bindings
    EapClientFfi.initializeBindings();

    // Create native client
    _ffi.create();

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
      await disconnect();
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
    _log(LogLevel.information, 'Starting connect...');

    _log(LogLevel.debug, 'Calling FFI connect...');
    final result = _ffi.connect();
    _log(LogLevel.debug, 'FFI connect result: $result');
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw EapException('Connect failed: $error (code: $result)');
    }
    _log(LogLevel.information, 'Connect complete');
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    _checkInitialized();

    final result = _ffi.disconnect();
    if (result != 0) {
      final error = _ffi.getLastError() ?? 'Unknown error';
      throw EapException('Disconnect failed: $error (code: $result)');
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
      throw EapException('Enable gaze failed: $error (code: $result)');
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
      throw EapException('Enable video failed: $error (code: $result)');
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
      throw EapException('Enable device logging failed: $error (code: $result)');
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
      throw EapException('Enable positioning failed: $error (code: $result)');
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
      throw EapException('Enable control stream failed: $error (code: $result)');
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
      throw EapException('Send control request failed: $error (code: $result)');
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
      throw EapException('Send display info failed: $error (code: $result)');
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
      throw EapException('Not connected to device');
    }

    // Offload hash computation + native memory copy to a background isolate
    // so the UI thread doesn't freeze for large files (500MB+ = ~300-500ms).
    // malloc uses the system allocator, so the pointer is valid across isolates.
    final prepared = await compute(_prepareUploadData, fileData);

    final (dataAddress, hashBytes) = prepared;
    if (dataAddress == 0) {
      throw EapException('Failed to allocate native memory for file data');
    }

    // Trivial main-thread work: pass the pointer to native (instant FFI call)
    final nativeData = Pointer<Uint8>.fromAddress(dataAddress);
    final nativeHash = calloc<Uint8>(32);
    if (nativeHash == nullptr) {
      malloc.free(nativeData);
      throw EapException('Failed to allocate memory for hash');
    }
    try {
      nativeHash.asTypedList(32).setAll(0, hashBytes);
      final result = _ffi.uploadFile(nativeData, fileData.length, devicePath, nativeHash);
      if (result != 0) {
        // Native did NOT take ownership — free here
        malloc.free(nativeData);
        throw EapException('File upload start failed (code: $result)');
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
            throw EapException('Upload timed out waiting for device confirmation');
          }
          throw EapException('Upload failed: ${status.errorMessage}');
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
      throw EapException('Start calibration failed: $error (code: $result)');
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
      throw EapException('Collect calibration points failed: $error (code: $result)');
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
      throw EapException('Abort calibration failed: $error (code: $result)');
    }
  }
}

/// Exception thrown by EapClient operations
class EapException implements Exception {
  final String message;

  EapException(this.message);

  @override
  String toString() => 'EapException: $message';
}
