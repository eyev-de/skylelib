// Manual FFI bindings for flutter_eap bridge
// Based on flutter_eap_bridge.h

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'ffi_structs.dart';

// Opaque type for eap_client pointer
final class EapClientNative extends Opaque {}

// =============================================================================
// Dart Callback Type Definitions (matching C function pointers)
// Now using structs passed by value to prevent stack corruption
// =============================================================================

typedef DartGazeCallback = Void Function(EapGazeResponse gaze, Pointer<Void> userData);

typedef DartPositioningCallback = Void Function(EapPositioningResponse positioning, Pointer<Void> userData);

typedef DartVersionCallback = Void Function(EapVersionResponse version, Pointer<Void> userData);

typedef DartControlCallback = Void Function(EapControlMessage control, Pointer<Void> userData);

typedef DartCalibrationPointCallback = Void Function(EapNextCalibrationPoint point, Pointer<Void> userData);

typedef DartCalibrationProgressCallback = Void Function(EapCollectingCalibrationPoints progress, Pointer<Void> userData);

typedef DartCalibrationPausedCallback = Void Function(Pointer<Void> userData);

typedef DartCalibrationFinishedCallback = Void Function(EapFinishedCalibration result, Pointer<Void> userData);

typedef DartVideoCallback = Void Function(Pointer<Uint8> data, Uint32 length, Uint16 width, Uint16 height, Uint8 channels, Pointer<Void> userData);

typedef DartFileStatusCallback = Void Function(Uint16 status, Uint16 progress, Pointer<Utf8> errorMessage, Pointer<Void> userData);

typedef DartLoggingCallback = Void Function(Uint8 level, Pointer<Utf8> message, Int64 timestampMs, Pointer<Void> userData);

typedef DartStateCallback = Void Function(Int32 state, Pointer<Void> userData);

typedef DartErrorCallback = Void Function(Pointer<Utf8> errorMessage, Pointer<Void> userData);

// =============================================================================
// Callbacks Structure (matches flutter_eap_callbacks from C)
// =============================================================================

final class FlutterEapCallbacks extends Struct {
  external Pointer<NativeFunction<DartGazeCallback>> onGaze;
  external Pointer<NativeFunction<DartPositioningCallback>> onPositioning;
  external Pointer<NativeFunction<DartVersionCallback>> onVersion;
  external Pointer<NativeFunction<DartControlCallback>> onControl;
  external Pointer<NativeFunction<DartCalibrationPointCallback>> onCalibrationPoint;
  external Pointer<NativeFunction<DartCalibrationProgressCallback>> onCalibrationProgress;
  external Pointer<NativeFunction<DartCalibrationPausedCallback>> onCalibrationPaused;
  external Pointer<NativeFunction<DartCalibrationFinishedCallback>> onCalibrationFinished;
  external Pointer<NativeFunction<DartVideoCallback>> onVideo;
  external Pointer<NativeFunction<DartFileStatusCallback>> onFileStatus;
  external Pointer<NativeFunction<DartLoggingCallback>> onLogging;
  external Pointer<NativeFunction<DartStateCallback>> onStateChange;
  external Pointer<NativeFunction<DartErrorCallback>> onError;
  external Pointer<Void> userData;
}

// =============================================================================
// C Function Signatures
// =============================================================================

// Client lifecycle (new singleton API)
typedef FlutterEapIsInitializedNative = Bool Function();
typedef FlutterEapIsInitialized = bool Function();

typedef FlutterEapGetInstanceNative = Pointer<EapClientNative> Function();
typedef FlutterEapGetInstance = Pointer<EapClientNative> Function();

typedef FlutterEapSetCallbacksNative = Int32 Function(Pointer<EapClientNative> client, Pointer<FlutterEapCallbacks> callbacks);
typedef FlutterEapSetCallbacks = int Function(Pointer<EapClientNative> client, Pointer<FlutterEapCallbacks> callbacks);

typedef FlutterEapClearCallbacksNative = Void Function(Pointer<EapClientNative> client);
typedef FlutterEapClearCallbacks = void Function(Pointer<EapClientNative> client);

typedef FlutterEapDestroyNative = Void Function(Pointer<EapClientNative> client);
typedef FlutterEapDestroy = void Function(Pointer<EapClientNative> client);

// Connection control
typedef FlutterEapConnectNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapConnect = int Function(Pointer<EapClientNative> client);

typedef FlutterEapDisconnectNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapDisconnect = int Function(Pointer<EapClientNative> client);

// Feature control
typedef FlutterEapEnableStreamNative = Int32 Function(Pointer<EapClientNative> client, Bool enable);
typedef FlutterEapEnableStream = int Function(Pointer<EapClientNative> client, bool enable);

typedef FlutterEapRequestVersionNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapRequestVersion = int Function(Pointer<EapClientNative> client);

// Calibration control
typedef FlutterEapStartCalibrationNative = Int32 Function(Pointer<EapClientNative> client, Pointer<EapConfigureCalibration> config);
typedef FlutterEapStartCalibration = int Function(Pointer<EapClientNative> client, Pointer<EapConfigureCalibration> config);

typedef FlutterEapCollectCalibrationPointsNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapCollectCalibrationPoints = int Function(Pointer<EapClientNative> client);

typedef FlutterEapAbortCalibrationNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapAbortCalibration = int Function(Pointer<EapClientNative> client);

typedef FlutterEapSendControlNative = Int32 Function(Pointer<EapClientNative> client, Pointer<EapControlMessage> message);
typedef FlutterEapSendControl = int Function(Pointer<EapClientNative> client, Pointer<EapControlMessage> message);

typedef FlutterEapSendDisplayInfoNative = Int32 Function(Pointer<EapClientNative> client, Pointer<EapSetDisplayInfo> info);
typedef FlutterEapSendDisplayInfo = int Function(Pointer<EapClientNative> client, Pointer<EapSetDisplayInfo> info);

// USB data feeding functions REMOVED - now handled by Kotlin via JNI callbacks
// feedUsbData, getPendingWrite, clearPendingWrite no longer exist

// File transfer
typedef FlutterEapUploadFileNative = Int32 Function(Pointer<EapClientNative> client, Pointer<Utf8> path, Pointer<Uint8> data, Uint32 dataLen, Pointer<Uint8> sha256Hash);
typedef FlutterEapUploadFile = int Function(Pointer<EapClientNative> client, Pointer<Utf8> path, Pointer<Uint8> data, int dataLen, Pointer<Uint8> sha256Hash);

typedef FlutterEapCancelUploadNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapCancelUpload = int Function(Pointer<EapClientNative> client);

// State query
typedef FlutterEapGetStateNative = Int32 Function(Pointer<EapClientNative> client);
typedef FlutterEapGetState = int Function(Pointer<EapClientNative> client);

typedef FlutterEapGetLastErrorNative = Pointer<Utf8> Function(Pointer<EapClientNative> client);
typedef FlutterEapGetLastError = Pointer<Utf8> Function(Pointer<EapClientNative> client);

// Memory management (Windows: CRT free vs CoTaskMemFree mismatch)
typedef FlutterEapFreeNative = Void Function(Pointer<Void> ptr);
typedef FlutterEapFree = void Function(Pointer<Void> ptr);

// =============================================================================
// Bindings Class
// =============================================================================

/// Low-level FFI bindings to flutter_eap C library
/// Do not use directly - use EapClient instead
class EapClientBindings {
  final DynamicLibrary _dylib;

  late final FlutterEapIsInitialized isInitialized;
  late final FlutterEapGetInstance getInstance;
  late final FlutterEapSetCallbacks setCallbacks;
  late final FlutterEapClearCallbacks clearCallbacks;
  late final FlutterEapDestroy destroy;
  late final FlutterEapConnect connect;
  late final FlutterEapDisconnect disconnect;
  late final FlutterEapEnableStream enableGaze;
  late final FlutterEapEnableStream enablePositioning;
  late final FlutterEapRequestVersion requestVersion;
  late final FlutterEapEnableStream enableControl;
  late final FlutterEapSendControl sendControl;
  late final FlutterEapSendDisplayInfo sendDisplayInfo;
  late final FlutterEapStartCalibration startCalibration;
  late final FlutterEapCollectCalibrationPoints collectCalibrationPoints;
  late final FlutterEapAbortCalibration abortCalibration;
  late final FlutterEapEnableStream enableVideo;
  late final FlutterEapEnableStream enableLogging;
  late final FlutterEapUploadFile uploadFile;
  late final FlutterEapCancelUpload cancelUpload;
  // feedUsbData, getPendingWrite, clearPendingWrite REMOVED
  late final FlutterEapGetState getState;
  late final FlutterEapGetLastError getLastError;
  late final FlutterEapFree? nativeFree;

  /// Native function pointer for flutter_eap_free, suitable for
  /// [NativeFinalizer] / [Pointer.asTypedList] finalizer parameter.
  late final Pointer<NativeFinalizerFunction>? nativeFreeFinalizer;

  EapClientBindings(this._dylib) {
    isInitialized = _dylib.lookup<NativeFunction<FlutterEapIsInitializedNative>>('flutter_eap_is_initialized').asFunction();

    getInstance = _dylib.lookup<NativeFunction<FlutterEapGetInstanceNative>>('flutter_eap_get_instance').asFunction();

    setCallbacks = _dylib.lookup<NativeFunction<FlutterEapSetCallbacksNative>>('flutter_eap_set_callbacks').asFunction();

    clearCallbacks = _dylib.lookup<NativeFunction<FlutterEapClearCallbacksNative>>('flutter_eap_clear_callbacks').asFunction();

    destroy = _dylib.lookup<NativeFunction<FlutterEapDestroyNative>>('flutter_eap_destroy').asFunction();

    connect = _dylib.lookup<NativeFunction<FlutterEapConnectNative>>('flutter_eap_connect').asFunction();

    disconnect = _dylib.lookup<NativeFunction<FlutterEapDisconnectNative>>('flutter_eap_disconnect').asFunction();

    enableGaze = _dylib.lookup<NativeFunction<FlutterEapEnableStreamNative>>('flutter_eap_enable_gaze').asFunction();

    enablePositioning = _dylib.lookup<NativeFunction<FlutterEapEnableStreamNative>>('flutter_eap_enable_positioning').asFunction();

    requestVersion = _dylib.lookup<NativeFunction<FlutterEapRequestVersionNative>>('flutter_eap_request_version').asFunction();

    enableControl = _dylib.lookup<NativeFunction<FlutterEapEnableStreamNative>>('flutter_eap_enable_control').asFunction();

    sendControl = _dylib.lookup<NativeFunction<FlutterEapSendControlNative>>('flutter_eap_send_control').asFunction();

    sendDisplayInfo = _dylib.lookup<NativeFunction<FlutterEapSendDisplayInfoNative>>('flutter_eap_send_display_info').asFunction();

    startCalibration = _dylib.lookup<NativeFunction<FlutterEapStartCalibrationNative>>('flutter_eap_start_calibration').asFunction();

    collectCalibrationPoints = _dylib.lookup<NativeFunction<FlutterEapCollectCalibrationPointsNative>>('flutter_eap_collect_calibration_points').asFunction();

    abortCalibration = _dylib.lookup<NativeFunction<FlutterEapAbortCalibrationNative>>('flutter_eap_abort_calibration').asFunction();

    enableVideo = _dylib.lookup<NativeFunction<FlutterEapEnableStreamNative>>('flutter_eap_enable_video').asFunction();

    enableLogging = _dylib.lookup<NativeFunction<FlutterEapEnableStreamNative>>('flutter_eap_enable_logging').asFunction();

    uploadFile = _dylib.lookup<NativeFunction<FlutterEapUploadFileNative>>('flutter_eap_upload_file').asFunction();

    cancelUpload = _dylib.lookup<NativeFunction<FlutterEapCancelUploadNative>>('flutter_eap_cancel_upload').asFunction();

    // feedUsbData, getPendingWrite, clearPendingWrite lookups REMOVED

    getState = _dylib.lookup<NativeFunction<FlutterEapGetStateNative>>('flutter_eap_get_state').asFunction();

    getLastError = _dylib.lookup<NativeFunction<FlutterEapGetLastErrorNative>>('flutter_eap_get_last_error').asFunction();

    // Free memory allocated by the C bridge. Exported on all platforms so that
    // Dart can attach a NativeFinalizer for zero-copy video frame ownership.
    // On Windows this is critical (CRT free != CoTaskMemFree); on other
    // platforms it wraps the standard free().
    try {
      nativeFree = _dylib.lookup<NativeFunction<FlutterEapFreeNative>>('flutter_eap_free').asFunction();
      nativeFreeFinalizer = _dylib.lookup<NativeFinalizerFunction>('flutter_eap_free');
    } catch (_) {
      nativeFree = null;
      nativeFreeFinalizer = null;
    }
  }
}
