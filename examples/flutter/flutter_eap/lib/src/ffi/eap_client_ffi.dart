/// FFI wrapper for EAP client
/// Manages native client lifecycle and callbacks

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'eap_client_bindings.dart';
import 'ffi_structs.dart';
import '../models/models.dart';

/// FFI wrapper for the native EAP client
/// Handles native library loading, callback registration, and memory management
class EapClientFfi {
  static EapClientBindings? _bindings;
  static const _methodChannel = MethodChannel('flutter_eap/usb');

  Pointer<EapClientNative>? _clientPtr;
  Pointer<FlutterEapCallbacks>? _callbacksPtr;

  // Track if we've been destroyed to prevent double-destroy
  bool _isDestroyed = false;

  // NativeCallable listeners (for callbacks from native threads)
  NativeCallable<DartGazeCallback>? _gazeCallable;
  NativeCallable<DartPositioningCallback>? _positioningCallable;
  NativeCallable<DartVersionCallback>? _versionCallable;
  NativeCallable<DartControlCallback>? _controlCallable;
  NativeCallable<DartCalibrationPointCallback>? _calibrationPointCallable;
  NativeCallable<DartCalibrationProgressCallback>? _calibrationProgressCallable;
  NativeCallable<DartCalibrationPausedCallback>? _calibrationPausedCallable;
  NativeCallable<DartCalibrationFinishedCallback>? _calibrationFinishedCallable;
  NativeCallable<DartVideoCallback>? _videoCallable;
  NativeCallable<DartFileStatusCallback>? _fileStatusCallable;
  NativeCallable<DartLoggingCallback>? _loggingCallable;
  NativeCallable<DartStateCallback>? _stateCallable;
  NativeCallable<DartErrorCallback>? _errorCallable;

  // Stream controllers for callbacks
  final _gazeController = StreamController<GazesData>.broadcast();
  final _positioningController = StreamController<FaceData>.broadcast();
  final _controlController = StreamController<ControlData>.broadcast();
  final _calibrationController = StreamController<CalibrationMessage>.broadcast();
  final _videoController = StreamController<VideoFrame>.broadcast();
  final _fileStatusController = StreamController<FileUploadStatus>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _logController = StreamController<EapLogMessage>.broadcast();
  final _deviceLogController = StreamController<EapLogMessage>.broadcast();

  // Completer for version request with timeout
  Completer<VersionData>? _versionCompleter;
  Timer? _versionTimeout;

  // Public streams
  Stream<GazesData> get gazeDataStream => _gazeController.stream;
  Stream<FaceData> get positioningDataStream => _positioningController.stream;
  Stream<ControlData> get controlDataStream => _controlController.stream;
  Stream<CalibrationMessage> get calibrationStream => _calibrationController.stream;
  Stream<VideoFrame> get videoDataStream => _videoController.stream;
  Stream<FileUploadStatus> get fileStatusStream => _fileStatusController.stream;
  Stream<ConnectionState> get stateStream => _stateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<EapLogMessage> get logStream => _logController.stream;

  /// Log lines streamed from the firmware over EAP. Distinct from [logStream],
  /// which carries diagnostics emitted by this Dart layer.
  Stream<EapLogMessage> get deviceLogStream => _deviceLogController.stream;

  /// Emit a diagnostic message on [logStream].
  void emitLog(LogLevel level, String source, String message) {
    if (_logController.isClosed) return;
    _logController.add(EapLogMessage(level: level, source: source, message: message));
  }

  /// Static variant used by native-thread callbacks that only have access to
  /// the class, not an instance.
  static void _emitLog(LogLevel level, String source, String message) {
    final instance = _instance;
    if (instance == null) {
      // ignore: avoid_print
      print('[$source] $message');
      return;
    }
    instance.emitLog(level, source, message);
  }

  /// Initialize FFI bindings (call once at app startup)
  static void initializeBindings() {
    if (_bindings != null) return;

    final dylib = _loadLibrary();
    _bindings = EapClientBindings(dylib);
  }

  /// Load native library based on platform
  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libflutter_eap.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('flutter_eap_plugin.dll');
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} is not supported');
    }
  }

  /// Create EAP client with callbacks
  ///
  /// Handles hot restart gracefully: if a native client already exists (surviving
  /// from before the Dart VM restart), swaps Dart callback pointers without
  /// destroying the native client. This keeps the USB connection alive across
  /// hot restarts.
  void create() {
    if (_bindings == null) {
      throw StateError('Bindings not initialized - call initializeBindings()');
    }

    // Unregister any existing instance (from previous hot restart cycle)
    _unregisterInstance(hashCode);

    _isDestroyed = false;

    // Detect hot restart: check if bridge context exists BEFORE calling getInstance()
    // (getInstance creates on demand, so it always returns non-null)
    final isHotRestart = _bindings!.isInitialized();

    if (isHotRestart) {
      // HOT RESTART PATH: Native client is alive (background thread running,
      // USB transport active). Just swap the Dart callback pointers.
      _emitLog(LogLevel.information, 'EapClientFfi', 'Hot restart detected - swapping callbacks (keeping connection alive)');

      // Clear stale Dart callbacks first (mutex-protected in C bridge).
      // The C adapter functions stay registered - they'll return early for
      // any callbacks that arrive between clear and set.
      final existingClientPtr = _bindings!.getInstance();
      _bindings!.clearCallbacks(existingClientPtr);
    }

    // Create new NativeCallable listeners for thread-safe callbacks
    _gazeCallable = NativeCallable<DartGazeCallback>.listener(_onGazeCallback);
    _positioningCallable = NativeCallable<DartPositioningCallback>.listener(_onPositioningCallback);
    _versionCallable = NativeCallable<DartVersionCallback>.listener(_onVersionCallback);
    _controlCallable = NativeCallable<DartControlCallback>.listener(_onControlCallback);
    _calibrationPointCallable = NativeCallable<DartCalibrationPointCallback>.listener(_onCalibrationPointCallback);
    _calibrationProgressCallable = NativeCallable<DartCalibrationProgressCallback>.listener(_onCalibrationProgressCallback);
    _calibrationPausedCallable = NativeCallable<DartCalibrationPausedCallback>.listener(_onCalibrationPausedCallback);
    _calibrationFinishedCallable = NativeCallable<DartCalibrationFinishedCallback>.listener(_onCalibrationFinishedCallback);
    _videoCallable = NativeCallable<DartVideoCallback>.listener(_onVideoCallback);
    _fileStatusCallable = NativeCallable<DartFileStatusCallback>.listener(_onFileStatusCallback);
    _loggingCallable = NativeCallable<DartLoggingCallback>.listener(_onLoggingCallback);
    _stateCallable = NativeCallable<DartStateCallback>.listener(_onStateCallback);
    _errorCallable = NativeCallable<DartErrorCallback>.listener(_onErrorCallback);

    // Allocate callbacks structure
    _callbacksPtr = calloc<FlutterEapCallbacks>();
    _callbacksPtr!.ref
      ..onGaze = _gazeCallable!.nativeFunction
      ..onPositioning = _positioningCallable!.nativeFunction
      ..onVersion = _versionCallable!.nativeFunction
      ..onControl = _controlCallable!.nativeFunction
      ..onCalibrationPoint = _calibrationPointCallable!.nativeFunction
      ..onCalibrationProgress = _calibrationProgressCallable!.nativeFunction
      ..onCalibrationPaused = _calibrationPausedCallable!.nativeFunction
      ..onCalibrationFinished = _calibrationFinishedCallable!.nativeFunction
      ..onVideo = _videoCallable!.nativeFunction
      ..onFileStatus = _fileStatusCallable!.nativeFunction
      ..onLogging = _loggingCallable!.nativeFunction
      ..onStateChange = _stateCallable!.nativeFunction
      ..onError = _errorCallable!.nativeFunction
      ..userData = Pointer.fromAddress(hashCode); // Use Dart object hash as ID

    // Register this instance for callback lookup
    _registerInstance(hashCode, this);

    if (isHotRestart) {
      // Reuse existing native client - just install new callbacks
      _clientPtr = _bindings!.getInstance();

      final result = _bindings!.setCallbacks(_clientPtr!, _callbacksPtr!);
      if (result != 0) {
        _cleanup();
        throw StateError('Failed to set callbacks on existing client (error: $result)');
      }

      _emitLog(LogLevel.information, 'EapClientFfi', 'Callbacks swapped successfully - connection preserved');
      // Skip transport configuration - it's still running from before hot restart
      return;
    }

    // FRESH START PATH: No existing client, create everything from scratch
    _clientPtr = _bindings!.getInstance();

    if (_clientPtr == null || _clientPtr!.address == 0) {
      _cleanup();
      throw StateError('Failed to get native client instance');
    }

    // Set callbacks on the singleton client
    final result = _bindings!.setCallbacks(_clientPtr!, _callbacksPtr!);
    if (result != 0) {
      _cleanup();
      throw StateError('Failed to set callbacks (error: $result)');
    }

    // Signal native layer to configure transport now that Dart callbacks are ready
    // This starts the C background thread which will detect USB and begin handshake
    // Android: Kotlin configures USB Host transport via JNI
    // iOS: Swift configures ExternalAccessory transport via C function pointers
    // macOS: C configures IOKit USB transport directly
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
      _configureTransport();
    }
  }

  /// Signal Kotlin to configure native transport
  /// This must be called AFTER callbacks are set to prevent race condition
  Future<void> _configureTransport() async {
    try {
      final success = await _methodChannel.invokeMethod<bool>('configureTransport');
      if (success == true) {
        _emitLog(LogLevel.information, 'EapClientFfi', 'Transport configured successfully');
      } else {
        _emitLog(LogLevel.warning, 'EapClientFfi', 'Failed to configure transport');
      }
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error configuring transport: $e');
    }
  }

  /// Get native client pointer (for passing to Kotlin/Swift via method channel)
  int getClientPointer() {
    _checkClient();
    return _clientPtr!.address;
  }

  /// Destroy client and cleanup resources
  ///
  /// CRITICAL: Order of operations matters to prevent "Callback invoked after deleted":
  /// 1. Clear callbacks in native code (stops background thread from calling them)
  /// 2. Destroy native client (stops background thread and waits for it to finish)
  /// 3. Only then close NativeCallable listeners
  void destroy() {
    if (_isDestroyed) {
      _emitLog(LogLevel.debug, 'EapClientFfi', 'Already destroyed, skipping');
      return;
    }
    _isDestroyed = true;

    _emitLog(LogLevel.information, 'EapClientFfi', 'destroy() called - starting cleanup');

    // Step 1: Clear callbacks in native code FIRST
    // This prevents the native background thread from invoking Dart callbacks
    if (_clientPtr != null && _bindings != null) {
      _emitLog(LogLevel.debug, 'EapClientFfi', 'Clearing native callbacks');
      _bindings!.clearCallbacks(_clientPtr!);
    }

    // Step 2: Destroy native client (this stops background thread and waits for it)
    if (_clientPtr != null && _bindings != null) {
      _emitLog(LogLevel.debug, 'EapClientFfi', 'Destroying native client');
      _bindings!.destroy(_clientPtr!);
      _clientPtr = null;
    }

    // Step 3: Unregister instance (makes any stray callbacks no-op)
    _unregisterInstance(hashCode);

    // Step 4: Now it's safe to close NativeCallable listeners
    _emitLog(LogLevel.debug, 'EapClientFfi', 'Cleaning up Dart resources');
    _cleanup();

    _emitLog(LogLevel.information, 'EapClientFfi', 'destroy() complete');
  }

  void _cleanup() {
    // Cancel version timeout and completer
    _versionTimeout?.cancel();
    _versionTimeout = null;
    if (_versionCompleter != null && !_versionCompleter!.isCompleted) {
      _versionCompleter!.completeError(StateError('Client destroyed'));
    }
    _versionCompleter = null;

    if (_callbacksPtr != null) {
      calloc.free(_callbacksPtr!);
      _callbacksPtr = null;
    }

    // Close NativeCallable listeners
    _gazeCallable?.close();
    _positioningCallable?.close();
    _versionCallable?.close();
    _controlCallable?.close();
    _calibrationPointCallable?.close();
    _calibrationProgressCallable?.close();
    _calibrationPausedCallable?.close();
    _calibrationFinishedCallable?.close();
    _videoCallable?.close();
    _fileStatusCallable?.close();
    _loggingCallable?.close();
    _stateCallable?.close();
    _errorCallable?.close();

    _gazeCallable = null;
    _positioningCallable = null;
    _versionCallable = null;
    _controlCallable = null;
    _calibrationPointCallable = null;
    _calibrationProgressCallable = null;
    _calibrationPausedCallable = null;
    _calibrationFinishedCallable = null;
    _videoCallable = null;
    _fileStatusCallable = null;
    _loggingCallable = null;
    _stateCallable = null;
    _errorCallable = null;

    // Close stream controllers
    _gazeController.close();
    _positioningController.close();
    _controlController.close();
    _calibrationController.close();
    _videoController.close();
    _fileStatusController.close();
    _stateController.close();
    _errorController.close();
    _logController.close();
    _deviceLogController.close();
  }

  // ==========================================================================
  // Public API Methods
  // ==========================================================================

  int connect() {
    _checkClient();
    return _bindings!.connect(_clientPtr!);
  }

  int disconnect() {
    _checkClient();
    return _bindings!.disconnect(_clientPtr!);
  }

  int enableGaze(bool enable) {
    _checkClient();
    return _bindings!.enableGaze(_clientPtr!, enable);
  }

  int enablePositioning(bool enable) {
    _checkClient();
    return _bindings!.enablePositioning(_clientPtr!, enable);
  }

  /// Request version and return a Future with 200ms timeout
  Future<VersionData> requestVersion() async {
    _checkClient();

    // If a request is already in progress, return the existing future
    if (_versionCompleter != null && !_versionCompleter!.isCompleted) {
      return _versionCompleter!.future;
    }

    // Cancel any existing timeout
    _versionTimeout?.cancel();

    // Create new completer
    _versionCompleter = Completer<VersionData>();

    // Set up timeout (2000ms - Windows USB needs more time)
    _versionTimeout = Timer(const Duration(milliseconds: 2000), () {
      if (_versionCompleter != null && !_versionCompleter!.isCompleted) {
        _versionCompleter!.completeError(TimeoutException('Version request timed out after 2000ms'));
        _versionCompleter = null;
      }
    });

    // Send request to native code
    final result = _bindings!.requestVersion(_clientPtr!);
    if (result != 0) {
      _versionTimeout?.cancel();
      _versionTimeout = null;
      final error = StateError('Failed to request version (error code: $result)');
      _versionCompleter!.completeError(error);
      _versionCompleter = null;
      throw error;
    }

    return _versionCompleter!.future;
  }

  int enableControl(bool enable) {
    _checkClient();
    return _bindings!.enableControl(_clientPtr!, enable);
  }

  int sendControl(ControlMessage message) {
    _checkClient();
    final ptr = calloc<EapControlMessage>();
    ptr.ref
      ..isStandbyEnabled = message.isStandbyEnabled
      ..isAutoPauseEnabled = message.isAutoPauseEnabled
      ..isPauseEnabled = message.isPauseEnabled
      ..trackingMode = message.trackingMode.value
      ..gazeFilter = message.gazeFilter
      ..fixationFilter = message.fixationFilter
      ..isAssistiveTouchEnabled = message.isAssistiveTouchEnabled
      ..showTrackingDetails = message.showTrackingDetails
      ..isHidEnabled = message.isHidEnabled
      ..isEthernetEnabled = message.isEthernetEnabled;
    final ret = _bindings!.sendControl(_clientPtr!, ptr);
    calloc.free(ptr);
    return ret;
  }

  int sendDisplayInfo(DisplayInfo info) {
    _checkClient();
    final ptr = calloc<EapSetDisplayInfo>();
    ptr.ref.resolution.width = info.resolution.width;
    ptr.ref.resolution.height = info.resolution.height;
    ptr.ref.sizeMm.width = info.sizeMm.width;
    ptr.ref.sizeMm.height = info.sizeMm.height;
    final ret = _bindings!.sendDisplayInfo(_clientPtr!, ptr);
    calloc.free(ptr);
    return ret;
  }

  int startCalibration(CalibrationConfig config) {
    _checkClient();
    final ptr = calloc<EapConfigureCalibration>();

    // Allocate and populate points array
    final pointsPtr = calloc<Uint8>(config.points.length);
    for (var i = 0; i < config.points.length; i++) {
      pointsPtr[i] = config.points[i];
    }

    // Allocate and populate coordinates array
    final coordinatesPtr = calloc<EapPointf>(config.coordinates.length);
    for (var i = 0; i < config.coordinates.length; i++) {
      coordinatesPtr[i].x = config.coordinates[i].x;
      coordinatesPtr[i].y = config.coordinates[i].y;
    }

    // Populate the calibration config struct
    ptr.ref
      ..pointsCount = config.points.length
      ..points = pointsPtr
      ..coordinatesCount = config.coordinates.length
      ..coordinates = coordinatesPtr;

    // Set resolution (Sizeu -> EapSizeu)
    ptr.ref.resolution.width = config.resolution.width;
    ptr.ref.resolution.height = config.resolution.height;

    // Set size (Size2d -> EapSizef)
    ptr.ref.size.width = config.size.width;
    ptr.ref.size.height = config.size.height;

    ptr.ref.improve = config.improve;

    final ret = _bindings!.startCalibration(_clientPtr!, ptr);

    // Clean up allocated memory
    calloc.free(ptr);
    calloc.free(pointsPtr);
    calloc.free(coordinatesPtr);
    return ret;
  }

  int collectCalibrationPoints() {
    _checkClient();
    return _bindings!.collectCalibrationPoints(_clientPtr!);
  }

  int abortCalibration() {
    _checkClient();
    return _bindings!.abortCalibration(_clientPtr!);
  }

  int enableVideo(bool enable) {
    _checkClient();
    return _bindings!.enableVideo(_clientPtr!, enable);
  }

  int enableLogging(bool enable) {
    _checkClient();
    return _bindings!.enableLogging(_clientPtr!, enable);
  }

  int uploadFile(Pointer<Uint8> data, int dataLen, String path, Pointer<Uint8> sha256Hash) {
    _checkClient();
    final pathPtr = path.toNativeUtf8();
    try {
      return _bindings!.uploadFile(_clientPtr!, pathPtr, data, dataLen, sha256Hash);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Upload file directly from a Uint8List.
  /// Uses malloc (no zero-fill) to avoid wasting time on large buffers.
  /// Native takes ownership of the buffer on success (frees it when upload
  /// thread finishes). On error, we free it here.
  int uploadFileFromTypedData(Uint8List fileData, String path, Pointer<Uint8> sha256Hash) {
    _checkClient();
    final nativeData = malloc<Uint8>(fileData.length);
    if (nativeData == nullptr) return -1;
    nativeData.asTypedList(fileData.length).setAll(0, fileData);
    final pathPtr = path.toNativeUtf8();
    try {
      final result = _bindings!.uploadFile(_clientPtr!, pathPtr, nativeData, fileData.length, sha256Hash);
      if (result != 0) {
        // Native did NOT take ownership — free here
        malloc.free(nativeData);
      }
      return result;
    } catch (e) {
      malloc.free(nativeData);
      rethrow;
    } finally {
      calloc.free(pathPtr);
    }
  }

  int cancelUpload() {
    _checkClient();
    return _bindings!.cancelUpload(_clientPtr!);
  }

  ConnectionState getState() {
    _checkClient();
    final stateValue = _bindings!.getState(_clientPtr!);
    return ConnectionState.fromValue(stateValue);
  }

  String? getLastError() {
    _checkClient();
    final errorPtr = _bindings!.getLastError(_clientPtr!);
    if (errorPtr.address == 0) {
      return null;
    }
    return errorPtr.toDartString();
  }

  void _checkClient() {
    if (_clientPtr == null) {
      throw StateError('Client not created - call create() first');
    }
    if (_bindings == null) {
      throw StateError('Bindings not initialized');
    }
  }

  // ==========================================================================
  // Static Callback Handlers (called from C)
  // ==========================================================================

  static EapClientFfi? _instance;

  /// Free memory allocated by the C bridge using the correct allocator.
  /// On Windows, Dart's malloc.free() calls CoTaskMemFree (COM heap) but the
  /// C bridge allocates with CRT malloc -- different heaps, instant crash.
  /// This calls the bridge's own free() when available, falling back to
  /// malloc.free() on platforms where the heaps match (macOS, Linux, etc).
  static void _nativeFree(Pointer<Void> ptr) {
    final free = _bindings?.nativeFree;
    if (free != null) {
      free(ptr);
    } else {
      malloc.free(ptr);
    }
  }

  static void _registerInstance(int hash, EapClientFfi instance) {
    _instance = instance;
  }

  static void _unregisterInstance(int hash) {
    _instance = null;
  }

  static void _onGazeCallback(EapGazeResponse gaze, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) {
      _emitLog(LogLevel.warning, 'EapClientFfi', '_onGazeCallback: No instance found');
      return;
    }

    // Struct is passed by value from C, so we have our own copy that can't be corrupted
    try {
      instance._gazeController.add(GazesData.fromEapGazeResponse(gaze));
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error parsing gaze: $e');
    }
  }

  static void _onPositioningCallback(EapPositioningResponse positioning, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) {
      _emitLog(LogLevel.warning, 'EapClientFfi', '_onPositioningCallback: No instance found');
      return;
    }

    // Struct is passed by value from C, so we have our own copy that can't be corrupted
    try {
      instance._positioningController.add(FaceData.fromEapPositioningResponse(positioning));
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error parsing positioning: $e');
    }
  }

  static void _onVersionCallback(EapVersionResponse version, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    try {
      final versionData = VersionData.fromEapVersionResponse(version);

      // Complete the future if there's a pending request
      if (instance._versionCompleter != null && !instance._versionCompleter!.isCompleted) {
        instance._versionTimeout?.cancel();
        instance._versionTimeout = null;
        instance._versionCompleter!.complete(versionData);
        instance._versionCompleter = null;
      }
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error parsing version: $e');
      // Must fail the completer so eapVersionDataProvider does not hang forever.
      if (instance._versionCompleter != null && !instance._versionCompleter!.isCompleted) {
        instance._versionTimeout?.cancel();
        instance._versionTimeout = null;
        instance._versionCompleter!.completeError(e);
        instance._versionCompleter = null;
      }
    }
  }

  static void _onControlCallback(EapControlMessage control, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    // Struct is passed by value from C, so we have our own copy that can't be corrupted
    try {
      final msg = ControlMessage(
        isStandbyEnabled: control.isStandbyEnabled,
        isAutoPauseEnabled: control.isAutoPauseEnabled,
        isPauseEnabled: control.isPauseEnabled,
        trackingMode: TrackingMode.fromValue(control.trackingMode),
        gazeFilter: control.gazeFilter,
        fixationFilter: control.fixationFilter,
        isAssistiveTouchEnabled: control.isAssistiveTouchEnabled,
        showTrackingDetails: control.showTrackingDetails,
        isHidEnabled: control.isHidEnabled,
        isEthernetEnabled: control.isEthernetEnabled,
      );
      _emitLog(LogLevel.debug, 'EapClientFfi', 'Control received: $msg');
      instance._controlController.add(msg);
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error parsing control: $e');
    }
  }

  static void _onCalibrationPointCallback(EapNextCalibrationPoint point, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    // Struct is passed by value from C, so we have our own copy that can't be corrupted
    instance._calibrationController.add(
      NextCalibrationPointMessage(point: CalibrationPoint(index: point.index, coordinates: Point2d(point.point.x, point.point.y))),
    );
  }

  static void _onCalibrationProgressCallback(EapCollectingCalibrationPoints progress, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    // Struct is passed by value from C, so we have our own copy that can't be corrupted
    instance._calibrationController.add(ProgressCalibrationPointMessage(progress: CalibrationProgress(index: progress.index, progress: progress.progress)));
  }

  static void _onCalibrationPausedCallback(Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    instance._calibrationController.add(PausedCalibrationMessage());
  }

  static void _onCalibrationFinishedCallback(EapFinishedCalibration result, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    final leftQualityPoints = <CalibrationQualityPoint>[];
    final rightQualityPoints = <CalibrationQualityPoint>[];

    for (var i = 0; i < result.leftCount; i++) {
      final qualityPoint = (result.left + i).ref;
      leftQualityPoints.add(
        CalibrationQualityPoint(
          index: qualityPoint.index,
          accuracy: Point2d.fromEapPointf(qualityPoint.accuracy),
          precision: qualityPoint.precision,
          quality: qualityPoint.quality,
        ),
      );
    }

    for (var i = 0; i < result.rightCount; i++) {
      final qualityPoint = (result.right + i).ref;
      rightQualityPoints.add(
        CalibrationQualityPoint(
          index: qualityPoint.index,
          accuracy: Point2d.fromEapPointf(qualityPoint.accuracy),
          precision: qualityPoint.precision,
          quality: qualityPoint.quality,
        ),
      );
    }

    instance._calibrationController.add(FinishedCalibrationMessage(result: CalibrationResult(left: leftQualityPoints, right: rightQualityPoints)));
  }

  static void _onVideoCallback(Pointer<Uint8> data, int length, int width, int height, int channels, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) {
      _nativeFree(data.cast());
      return;
    }

    // Drop incomplete frames (e.g. missing chunks in chunked transfer)
    if (length < width * height * channels) {
      _emitLog(LogLevel.warning, 'EapClientFfi', 'Video frame dropped: incomplete ${width}x$height x$channels, got $length bytes');
      _nativeFree(data.cast());
      return;
    }

    try {
      // Zero-copy: create a Dart Uint8List view backed by the C-allocated
      // buffer. A NativeFinalizer calls flutter_eap_free() when the Dart
      // GC collects the list, so no manual free and no memcpy.
      final finalizer = _bindings?.nativeFreeFinalizer;
      final Uint8List pixelData;
      if (finalizer != null) {
        pixelData = data.asTypedList(length, finalizer: finalizer);
      } else {
        // Fallback: copy if finalizer unavailable (should not happen)
        pixelData = Uint8List.fromList(data.asTypedList(length));
        _nativeFree(data.cast());
      }
      instance._videoController.add(VideoFrame(width: width, height: height, channels: channels, pixelData: pixelData));
    } catch (e) {
      _emitLog(LogLevel.error, 'EapClientFfi', 'Error parsing video frame: $e');
      _nativeFree(data.cast());
    }
  }

  static void _onFileStatusCallback(int status, int progress, Pointer<Utf8> errorMessage, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    // errorMessage is heap-allocated (_strdup/malloc) by the bridge -- free after reading.
    // Must use _nativeFree (CRT free) instead of malloc.free (CoTaskMemFree) on Windows.
    String? error;
    if (errorMessage.address != 0) {
      error = errorMessage.toDartString();
      _nativeFree(errorMessage.cast());
    }

    instance._fileStatusController.add(FileUploadStatus(status: FileTransferStatus.fromValue(status), progress: progress, errorMessage: error));
  }

  static void _onLoggingCallback(int level, Pointer<Utf8> message, int timestampMs, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) {
      // No instance — still need to free the heap-allocated message.
      if (message.address != 0) _nativeFree(message.cast());
      return;
    }

    String text = '';
    if (message.address != 0) {
      text = message.toDartString();
      _nativeFree(message.cast());
    }

    final lvl = (level >= 0 && level < LogLevel.values.length) ? LogLevel.values[level] : LogLevel.information;

    instance._deviceLogController.add(EapLogMessage(level: lvl, source: 'device', message: text, timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs)));
  }

  static void _onStateCallback(int state, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) {
      _emitLog(LogLevel.warning, 'EapClientFfi', '_onStateCallback: No instance found');
      return;
    }

    final stateObj = ConnectionState.fromValue(state);
    _emitLog(LogLevel.information, 'EapClientFfi', 'State changed: $stateObj');
    instance._stateController.add(stateObj);
  }

  static void _onErrorCallback(Pointer<Utf8> errorMessage, Pointer<Void> userData) {
    final instance = _instance;
    if (instance == null) return;

    instance._errorController.add(errorMessage.toDartString());
  }
}
