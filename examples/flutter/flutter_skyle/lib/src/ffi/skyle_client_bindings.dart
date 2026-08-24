// Manual FFI bindings for flutter_skyle bridge
// Based on flutter_skyle_bridge.h

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'ffi_structs.dart';

// Opaque type for skyle_client pointer
final class SkyleClientNative extends Opaque {}

// =============================================================================
// Dart Callback Type Definitions (matching C function pointers)
// Now using structs passed by value to prevent stack corruption
// =============================================================================

typedef DartGazeCallback = Void Function(SkyleGazeResponse gaze, Pointer<Void> userData);

typedef DartPositioningCallback = Void Function(SkylePositioningResponse positioning, Pointer<Void> userData);

typedef DartVersionCallback = Void Function(SkyleVersionResponse version, Pointer<Void> userData);

typedef DartControlCallback = Void Function(SkyleControlMessage control, Pointer<Void> userData);

typedef DartCalibrationPointCallback = Void Function(SkyleNextCalibrationPoint point, Pointer<Void> userData);

typedef DartCalibrationProgressCallback = Void Function(SkyleCollectingCalibrationPoints progress, Pointer<Void> userData);

typedef DartCalibrationPausedCallback = Void Function(Pointer<Void> userData);

typedef DartCalibrationFinishedCallback = Void Function(SkyleFinishedCalibration result, Pointer<Void> userData);

typedef DartVideoCallback = Void Function(Pointer<Uint8> data, Uint32 length, Uint16 width, Uint16 height, Uint8 channels, Pointer<Void> userData);

typedef DartFileStatusCallback = Void Function(Uint16 status, Uint16 progress, Pointer<Utf8> errorMessage, Pointer<Void> userData);

typedef DartLoggingCallback = Void Function(Uint8 level, Pointer<Utf8> message, Int64 timestampMs, Pointer<Void> userData);

typedef DartStateCallback = Void Function(Int32 state, Pointer<Void> userData);

typedef DartErrorCallback = Void Function(Pointer<Utf8> errorMessage, Pointer<Void> userData);

// Skyle Link: suspension state changed. `holder` is a heap-allocated copy
// (or nullptr when not suspended) that Dart must free with flutter_skyle_free.
typedef DartSuspendStateCallback = Void Function(Bool suspended, Pointer<Utf8> holder, Pointer<Void> userData);

// =============================================================================
// Callbacks Structure (matches flutter_skyle_callbacks from C)
// =============================================================================

final class FlutterSkyleCallbacks extends Struct {
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

  // Appended fields ONLY below this line: the layout above is ABI shared with
  // the native flutter_skyle_callbacks struct (single source of truth:
  // native/fanout/flutter_skyle_fanout.h; the darwin header keeps a
  // field-identical iOS copy) - field order must stay identical.
  // onSuspendState is dispatched by the subscriber fan-out on all pull-mode
  // platforms; it never fires on iOS (no Skyle Link supervisor there).
  external Pointer<NativeFunction<DartSuspendStateCallback>> onSuspendState;
}

// =============================================================================
// C Function Signatures
// =============================================================================

// Client lifecycle (new singleton API)
typedef FlutterSkyleIsInitializedNative = Bool Function();
typedef FlutterSkyleIsInitialized = bool Function();

typedef FlutterSkyleGetInstanceNative = Pointer<SkyleClientNative> Function();
typedef FlutterSkyleGetInstance = Pointer<SkyleClientNative> Function();

typedef FlutterSkyleSetCallbacksNative = Int32 Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks);
typedef FlutterSkyleSetCallbacks = int Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks);

typedef FlutterSkyleClearCallbacksNative = Void Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleClearCallbacks = void Function(Pointer<SkyleClientNative> client);

// Multi-engine callback fan-out (all pull-mode platforms: Android, macOS,
// Windows; iOS stays single-slot push mode): each Flutter engine registers
// its own subscriber and receives every callback independently.
typedef FlutterSkyleAddCallbacksNative = Int64 Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks);
typedef FlutterSkyleAddCallbacks = int Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks);

// Desktop variant with an engine token (PlatformDispatcher.engineId): a
// re-add with the same non-zero token atomically reaps the previous
// subscriber carrying it - the hot-restart path where no host-side (Kotlin)
// bookkeeping exists. Android keeps the plain add + reportSubscriberHandle.
typedef FlutterSkyleAddCallbacksEngineNative = Int64 Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks, Int64 engineToken);
typedef FlutterSkyleAddCallbacksEngine = int Function(Pointer<SkyleClientNative> client, Pointer<FlutterSkyleCallbacks> callbacks, int engineToken);

typedef FlutterSkyleRemoveCallbacksNative = Int32 Function(Pointer<SkyleClientNative> client, Int64 handle);
typedef FlutterSkyleRemoveCallbacks = int Function(Pointer<SkyleClientNative> client, int handle);

typedef FlutterSkyleDestroyNative = Void Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleDestroy = void Function(Pointer<SkyleClientNative> client);

// Connection control
typedef FlutterSkyleConnectNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleConnect = int Function(Pointer<SkyleClientNative> client);

typedef FlutterSkyleDisconnectNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleDisconnect = int Function(Pointer<SkyleClientNative> client);

// Feature control
typedef FlutterSkyleEnableStreamNative = Int32 Function(Pointer<SkyleClientNative> client, Bool enable);
typedef FlutterSkyleEnableStream = int Function(Pointer<SkyleClientNative> client, bool enable);

typedef FlutterSkyleRequestVersionNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleRequestVersion = int Function(Pointer<SkyleClientNative> client);

// Calibration control
typedef FlutterSkyleStartCalibrationNative = Int32 Function(Pointer<SkyleClientNative> client, Pointer<SkyleConfigureCalibration> config);
typedef FlutterSkyleStartCalibration = int Function(Pointer<SkyleClientNative> client, Pointer<SkyleConfigureCalibration> config);

typedef FlutterSkyleCollectCalibrationPointsNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleCollectCalibrationPoints = int Function(Pointer<SkyleClientNative> client);

typedef FlutterSkyleAbortCalibrationNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleAbortCalibration = int Function(Pointer<SkyleClientNative> client);

typedef FlutterSkyleSendControlNative = Int32 Function(Pointer<SkyleClientNative> client, Pointer<SkyleControlMessage> message);
typedef FlutterSkyleSendControl = int Function(Pointer<SkyleClientNative> client, Pointer<SkyleControlMessage> message);

typedef FlutterSkyleSendDisplayInfoNative = Int32 Function(Pointer<SkyleClientNative> client, Pointer<SkyleSetDisplayInfo> info);
typedef FlutterSkyleSendDisplayInfo = int Function(Pointer<SkyleClientNative> client, Pointer<SkyleSetDisplayInfo> info);

// USB data feeding functions REMOVED - now handled by Kotlin via JNI callbacks
// feedUsbData, getPendingWrite, clearPendingWrite no longer exist

// File transfer
typedef FlutterSkyleUploadFileNative = Int32 Function(Pointer<SkyleClientNative> client, Pointer<Utf8> path, Pointer<Uint8> data, Uint32 dataLen, Pointer<Uint8> sha256Hash);
typedef FlutterSkyleUploadFile = int Function(Pointer<SkyleClientNative> client, Pointer<Utf8> path, Pointer<Uint8> data, int dataLen, Pointer<Uint8> sha256Hash);

typedef FlutterSkyleCancelUploadNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleCancelUpload = int Function(Pointer<SkyleClientNative> client);

// State query
typedef FlutterSkyleGetStateNative = Int32 Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleGetState = int Function(Pointer<SkyleClientNative> client);

typedef FlutterSkyleGetLastErrorNative = Pointer<Utf8> Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleGetLastError = Pointer<Utf8> Function(Pointer<SkyleClientNative> client);

// Memory management (Windows: CRT free vs CoTaskMemFree mismatch)
typedef FlutterSkyleFreeNative = Void Function(Pointer<Void> ptr);
typedef FlutterSkyleFree = void Function(Pointer<Void> ptr);

// =============================================================================
// Skyle Link (multi-app sharing) - exported by the shared link glue that is
// compiled into every platform shim (flutter_skyle_link_glue.c). All symbols
// resolve from the SAME library the rest of the bindings use; they are
// nullable because an older prebuilt shim may not export them yet.
// =============================================================================

typedef FlutterSkyleLinkGlueInstallNative = Void Function(Pointer<SkyleClientNative> client);
typedef FlutterSkyleLinkGlueInstall = void Function(Pointer<SkyleClientNative> client);

typedef FlutterSkyleSetIdentityNative = Void Function(Pointer<Utf8> appId, Uint8 tier, Bool usbCapable);
typedef FlutterSkyleSetIdentity = void Function(Pointer<Utf8> appId, int tier, bool usbCapable);

typedef FlutterSkyleSetSupervisorEnabledNative = Void Function(Bool enabled);
typedef FlutterSkyleSetSupervisorEnabled = void Function(bool enabled);

// skyle_link_supervisor_mode: 0 disabled, 1 deciding, 2 owner, 3 client, 4 usb fallback.
typedef FlutterSkyleGetSupervisorModeNative = Int32 Function();
typedef FlutterSkyleGetSupervisorMode = int Function();

typedef FlutterSkyleLinkSetSuspendedNative = Int32 Function(Pointer<SkyleClientNative> client, Bool suspended);
typedef FlutterSkyleLinkSetSuspended = int Function(Pointer<SkyleClientNative> client, bool suspended);

typedef FlutterSkyleGetSuspensionStateNative = Void Function(Pointer<Bool> suspended, Pointer<Utf8> holderBuf, Size bufLen);
typedef FlutterSkyleGetSuspensionState = void Function(Pointer<Bool> suspended, Pointer<Utf8> holderBuf, int bufLen);


// =============================================================================
// Bindings Class
// =============================================================================

/// Low-level FFI bindings to flutter_skyle C library
/// Do not use directly - use SkyleClient instead
class SkyleClientBindings {
  final DynamicLibrary _dylib;

  late final FlutterSkyleIsInitialized isInitialized;
  late final FlutterSkyleGetInstance getInstance;
  late final FlutterSkyleSetCallbacks setCallbacks;
  late final FlutterSkyleClearCallbacks clearCallbacks;
  late final FlutterSkyleDestroy destroy;
  late final FlutterSkyleConnect connect;
  late final FlutterSkyleDisconnect disconnect;
  late final FlutterSkyleEnableStream enableGaze;
  late final FlutterSkyleEnableStream enablePositioning;
  late final FlutterSkyleRequestVersion requestVersion;
  late final FlutterSkyleEnableStream enableControl;
  late final FlutterSkyleSendControl sendControl;
  late final FlutterSkyleSendDisplayInfo sendDisplayInfo;
  late final FlutterSkyleStartCalibration startCalibration;
  late final FlutterSkyleCollectCalibrationPoints collectCalibrationPoints;
  late final FlutterSkyleAbortCalibration abortCalibration;
  late final FlutterSkyleEnableStream enableVideo;
  late final FlutterSkyleEnableStream enableLogging;
  late final FlutterSkyleUploadFile uploadFile;
  late final FlutterSkyleCancelUpload cancelUpload;
  // feedUsbData, getPendingWrite, clearPendingWrite REMOVED
  late final FlutterSkyleGetState getState;
  late final FlutterSkyleGetLastError getLastError;

  /// Multi-engine callback fan-out (all pull-mode platform bridges export
  /// these; null on iOS and against older single-slot desktop binaries).
  late final FlutterSkyleAddCallbacks? addCallbacks;
  late final FlutterSkyleAddCallbacksEngine? addCallbacksEngine;
  late final FlutterSkyleRemoveCallbacks? removeCallbacks;
  late final FlutterSkyleFree? nativeFree;

  /// Skyle Link symbols (shared link glue, all platforms). Null when the
  /// loaded shim predates Skyle Link support.
  late final FlutterSkyleLinkGlueInstall? linkGlueInstall;
  late final FlutterSkyleSetIdentity? setLinkIdentity;
  late final FlutterSkyleSetSupervisorEnabled? setSupervisorEnabled;
  late final FlutterSkyleGetSupervisorMode? getSupervisorMode;
  late final FlutterSkyleLinkSetSuspended? linkSetSuspended;
  late final FlutterSkyleGetSuspensionState? getSuspensionState;

  /// Native function pointer for flutter_skyle_free, suitable for
  /// [NativeFinalizer] / [Pointer.asTypedList] finalizer parameter.
  late final Pointer<NativeFinalizerFunction>? nativeFreeFinalizer;

  SkyleClientBindings(this._dylib) {
    isInitialized = _dylib.lookup<NativeFunction<FlutterSkyleIsInitializedNative>>('flutter_skyle_is_initialized').asFunction();

    getInstance = _dylib.lookup<NativeFunction<FlutterSkyleGetInstanceNative>>('flutter_skyle_get_instance').asFunction();

    setCallbacks = _dylib.lookup<NativeFunction<FlutterSkyleSetCallbacksNative>>('flutter_skyle_set_callbacks').asFunction();

    clearCallbacks = _dylib.lookup<NativeFunction<FlutterSkyleClearCallbacksNative>>('flutter_skyle_clear_callbacks').asFunction();

    destroy = _dylib.lookup<NativeFunction<FlutterSkyleDestroyNative>>('flutter_skyle_destroy').asFunction();

    connect = _dylib.lookup<NativeFunction<FlutterSkyleConnectNative>>('flutter_skyle_connect').asFunction();

    disconnect = _dylib.lookup<NativeFunction<FlutterSkyleDisconnectNative>>('flutter_skyle_disconnect').asFunction();

    enableGaze = _dylib.lookup<NativeFunction<FlutterSkyleEnableStreamNative>>('flutter_skyle_enable_gaze').asFunction();

    enablePositioning = _dylib.lookup<NativeFunction<FlutterSkyleEnableStreamNative>>('flutter_skyle_enable_positioning').asFunction();

    requestVersion = _dylib.lookup<NativeFunction<FlutterSkyleRequestVersionNative>>('flutter_skyle_request_version').asFunction();

    enableControl = _dylib.lookup<NativeFunction<FlutterSkyleEnableStreamNative>>('flutter_skyle_enable_control').asFunction();

    sendControl = _dylib.lookup<NativeFunction<FlutterSkyleSendControlNative>>('flutter_skyle_send_control').asFunction();

    sendDisplayInfo = _dylib.lookup<NativeFunction<FlutterSkyleSendDisplayInfoNative>>('flutter_skyle_send_display_info').asFunction();

    startCalibration = _dylib.lookup<NativeFunction<FlutterSkyleStartCalibrationNative>>('flutter_skyle_start_calibration').asFunction();

    collectCalibrationPoints = _dylib.lookup<NativeFunction<FlutterSkyleCollectCalibrationPointsNative>>('flutter_skyle_collect_calibration_points').asFunction();

    abortCalibration = _dylib.lookup<NativeFunction<FlutterSkyleAbortCalibrationNative>>('flutter_skyle_abort_calibration').asFunction();

    enableVideo = _dylib.lookup<NativeFunction<FlutterSkyleEnableStreamNative>>('flutter_skyle_enable_video').asFunction();

    enableLogging = _dylib.lookup<NativeFunction<FlutterSkyleEnableStreamNative>>('flutter_skyle_enable_logging').asFunction();

    uploadFile = _dylib.lookup<NativeFunction<FlutterSkyleUploadFileNative>>('flutter_skyle_upload_file').asFunction();

    cancelUpload = _dylib.lookup<NativeFunction<FlutterSkyleCancelUploadNative>>('flutter_skyle_cancel_upload').asFunction();

    // feedUsbData, getPendingWrite, clearPendingWrite lookups REMOVED

    getState = _dylib.lookup<NativeFunction<FlutterSkyleGetStateNative>>('flutter_skyle_get_state').asFunction();

    getLastError = _dylib.lookup<NativeFunction<FlutterSkyleGetLastErrorNative>>('flutter_skyle_get_last_error').asFunction();

    // Free memory allocated by the C bridge. Exported on all platforms so that
    // Dart can attach a NativeFinalizer for zero-copy video frame ownership.
    // On Windows this is critical (CRT free != CoTaskMemFree); on other
    // platforms it wraps the standard free().
    try {
      nativeFree = _dylib.lookup<NativeFunction<FlutterSkyleFreeNative>>('flutter_skyle_free').asFunction();
      nativeFreeFinalizer = _dylib.lookup<NativeFinalizerFunction>('flutter_skyle_free');
    } catch (_) {
      nativeFree = null;
      nativeFreeFinalizer = null;
    }

    // Multi-engine fan-out symbols (all pull-mode platform bridges; absent on
    // iOS and in older single-slot desktop binaries).
    try {
      addCallbacks = _dylib.lookup<NativeFunction<FlutterSkyleAddCallbacksNative>>('flutter_skyle_add_callbacks').asFunction();
      removeCallbacks = _dylib.lookup<NativeFunction<FlutterSkyleRemoveCallbacksNative>>('flutter_skyle_remove_callbacks').asFunction();
    } catch (_) {
      addCallbacks = null;
      removeCallbacks = null;
    }

    // Engine-token add (separate try block: an intermediate Android binary
    // exports the plain add but predates the engine variant).
    try {
      addCallbacksEngine = _dylib.lookup<NativeFunction<FlutterSkyleAddCallbacksEngineNative>>('flutter_skyle_add_callbacks_engine').asFunction();
    } catch (_) {
      addCallbacksEngine = null;
    }

    // Skyle Link glue symbols - ship in every current platform shim, but stay
    // nullable so the Dart layer degrades gracefully against an older binary
    // (all Skyle Link features then report unavailable instead of crashing).
    try {
      linkGlueInstall = _dylib.lookup<NativeFunction<FlutterSkyleLinkGlueInstallNative>>('flutter_skyle_link_glue_install').asFunction();
      setLinkIdentity = _dylib.lookup<NativeFunction<FlutterSkyleSetIdentityNative>>('flutter_skyle_set_identity').asFunction();
      setSupervisorEnabled = _dylib.lookup<NativeFunction<FlutterSkyleSetSupervisorEnabledNative>>('flutter_skyle_set_supervisor_enabled').asFunction();
      getSupervisorMode = _dylib.lookup<NativeFunction<FlutterSkyleGetSupervisorModeNative>>('flutter_skyle_get_supervisor_mode').asFunction();
      linkSetSuspended = _dylib.lookup<NativeFunction<FlutterSkyleLinkSetSuspendedNative>>('flutter_skyle_link_set_suspended').asFunction();
      getSuspensionState = _dylib.lookup<NativeFunction<FlutterSkyleGetSuspensionStateNative>>('flutter_skyle_get_suspension_state').asFunction();
    } catch (_) {
      linkGlueInstall = null;
      setLinkIdentity = null;
      setSupervisorEnabled = null;
      getSupervisorMode = null;
      linkSetSuspended = null;
      getSuspensionState = null;
    }
  }
}
