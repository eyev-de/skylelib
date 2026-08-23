/**
 * @file flutter_eap_fanout.h
 * @brief Shared multi-engine callback fan-out for the flutter_eap bridges.
 *
 * A pure semantic lift of the Android bridge's field-tested subscriber
 * machinery into platform-neutral C17, compiled into every PULL-MODE
 * platform's shim (Android: libflutter_eap.so via android/CMakeLists.txt,
 * macOS: the skylelib_unity.c unity include, Windows: flutter_eap_plugin.dll
 * via windows/CMakeLists.txt; Linux-ready, no shim exists there yet). iOS
 * stays single-slot push mode and does NOT compile this module.
 *
 * What lives here (and nowhere else):
 *  - The subscriber table: FLUTTER_EAP_MAX_SUBSCRIBERS slots, keyed by a
 *    monotonic int64 handle (0 = free slot), one slot per Flutter engine.
 *  - The C adapter set installed on the core eap_client, fanning every
 *    callback out to each subscriber that registered a non-NULL pointer.
 *  - The payload-copy rules: heap payloads (video frames, log / file-status
 *    strings, suspend holder ids) are allocated PER SUBSCRIBER because
 *    NativeCallable.listener delivers asynchronously - each Dart isolate
 *    frees its own copy with flutter_eap_free(). Video is converted to RGBA
 *    once; earlier subscribers get copies, the LAST one takes the original
 *    buffer. Calibration-result arrays are deep-copied per subscriber slot
 *    and stay module-owned (freed on the next dispatch or removal), matching
 *    the existing Dart no-free semantics.
 *  - The mutex discipline: one module mutex protects the table against the
 *    dispatch thread; add/remove/clear synchronize with in-flight dispatch,
 *    so after removal returns the subscriber's function pointers can no
 *    longer be invoked - the safe point to close Dart NativeCallables.
 *
 * The platform bridges keep their context/transport/ownership specifics and
 * define thin exported wrappers (declared below) that delegate here. This
 * header is also the single source of truth for the Dart-shared callback ABI
 * (the typedefs + flutter_eap_callbacks struct all bridges previously
 * duplicated); the iOS branch of the darwin bridge header keeps its own
 * field-identical copy.
 */

#ifndef FLUTTER_EAP_FANOUT_H
#define FLUTTER_EAP_FANOUT_H

#include <stdint.h>
#include <stdbool.h>
#include <skylelib/eap_client.h>

// Keep the Dart-facing wrapper symbols reachable from Dart FFI (mirrors
// EAP_EXPORT in the Apple bridge): `used` defeats -dead_strip, default
// visibility keeps them resolvable via DynamicLibrary.process() / dlsym.
// MSVC exports everything via WINDOWS_EXPORT_ALL_SYMBOLS.
#if defined(__GNUC__) || defined(__clang__)
#define EAP_FANOUT_EXPORT __attribute__((used)) __attribute__((visibility("default")))
#else
#define EAP_FANOUT_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Dart FFI Callback Function Pointer Types
// Passing complete C structs by value; layout is ABI shared with Dart
// (FlutterEapCallbacks in eap_client_bindings.dart).
// =============================================================================

/**
 * Gaze data callback (struct by value)
 * @param gaze eap_gaze_response struct passed by value
 * @param user_data User data pointer passed from Dart
 */
typedef void (*dart_gaze_callback)(
    eap_gaze_response gaze,
    void* user_data
);

/**
 * Positioning data callback (struct by value)
 * @param positioning eap_positioning_response struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_positioning_callback)(
    eap_positioning_response positioning,
    void* user_data
);

/**
 * Version callback (struct by value)
 * @param version eap_version_response struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_version_callback)(
    eap_version_response version,
    void* user_data
);

/**
 * Control callback (struct by value)
 * @param control eap_control_message struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_control_callback)(
    eap_control_message control,
    void* user_data
);

/**
 * Calibration point callback (struct by value)
 * @param point eap_next_calibration_point struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_point_callback)(
    eap_next_calibration_point point,
    void* user_data
);

/**
 * Calibration progress callback (struct by value)
 * @param progress eap_collecting_calibration_points struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_progress_callback)(
    eap_collecting_calibration_points progress,
    void* user_data
);

/**
 * Calibration paused callback
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_paused_callback)(
    void* user_data
);

/**
 * Calibration finished callback (struct by value)
 * @param result eap_finished_calibration struct passed by value
 * @param user_data User data pointer
 */
typedef void (*dart_calibration_finished_callback)(
    eap_finished_calibration result,
    void* user_data
);

/**
 * State change callback
 * @param state New connection state (eap_state enum value as int)
 * @param user_data User data pointer
 */
typedef void (*dart_state_callback)(
    int state,
    void* user_data
);

/**
 * Video frame callback
 * @param data RGBA pixel buffer, heap-allocated per subscriber. Dart takes
 *             ownership and frees it with flutter_eap_free() (NativeFinalizer).
 * @param length Length of pixel data in bytes
 * @param width Frame width in pixels
 * @param height Frame height in pixels
 * @param channels Number of channels (always 4 after conversion)
 * @param user_data User data pointer
 */
typedef void (*dart_video_callback)(
    const uint8_t* data,
    uint32_t length,
    uint16_t width,
    uint16_t height,
    uint8_t channels,
    void* user_data
);

/**
 * File status callback
 * @param status File transfer status (0=success, 1=progress, 2=failed)
 * @param progress Progress percentage 0-100 (valid when status==1)
 * @param error_message Heap-allocated error message (valid when status==2,
 *                      NULL otherwise). Dart MUST free it with
 *                      flutter_eap_free() after reading.
 * @param user_data User data pointer
 */
typedef void (*dart_file_status_callback)(
    uint16_t status,
    uint16_t progress,
    const char* error_message,
    void* user_data
);

/**
 * Error callback
 * @param error_message Null-terminated error message
 * @param user_data User data pointer
 */
typedef void (*dart_error_callback)(
    const char* error_message,
    void* user_data
);

/**
 * Skyle Link suspension state callback - eye-control suspension changed.
 * Fed from the link glue's cache (hub SUSPEND_CHANGED events when this
 * process serves the hub, the skyle_link suspend callback in local-link
 * client mode) via flutter_eap_fanout_dispatch_suspend_state().
 * @param suspended     Current suspension state
 * @param holder_app_id Heap-allocated UTF-8 copy of the holding app's id, or
 *                      NULL when not suspended. Dart MUST free it with
 *                      flutter_eap_free() after reading.
 * @param user_data     User data pointer
 */
typedef void (*dart_suspend_state_callback)(
    bool suspended,
    const char* holder_app_id,
    void* user_data
);

/**
 * Logging callback - device log line streamed over EAP.
 * @param level         Log severity (eap_log_level)
 * @param message       Heap-allocated UTF-8 message string. Dart MUST free
 *                      this with flutter_eap_free() after reading.
 * @param timestamp_ms  Device timestamp (Unix ms) from the EAP message header
 * @param user_data     User data pointer
 */
typedef void (*dart_logging_callback)(
    uint8_t level,
    const char* message,
    int64_t timestamp_ms,
    void* user_data
);

// =============================================================================
// Callback Registration Structure
// =============================================================================

/**
 * Structure holding all Dart callback function pointers for one subscriber.
 */
typedef struct {
    dart_gaze_callback on_gaze;
    dart_positioning_callback on_positioning;
    dart_version_callback on_version;
    dart_control_callback on_control;
    dart_calibration_point_callback on_calibration_point;
    dart_calibration_progress_callback on_calibration_progress;
    dart_calibration_paused_callback on_calibration_paused;
    dart_calibration_finished_callback on_calibration_finished;
    dart_video_callback on_video;
    dart_file_status_callback on_file_status;
    dart_logging_callback on_logging;
    dart_state_callback on_state_change;
    dart_error_callback on_error;
    void* user_data;  // Passed back to all callbacks
    // Appended fields ONLY below this line: the layout above is ABI shared
    // with Dart (FlutterEapCallbacks in eap_client_bindings.dart) and the
    // darwin bridge's iOS branch - all definitions must stay field-identical.
    dart_suspend_state_callback on_suspend_state;  // Skyle Link suspension fan-out
} flutter_eap_callbacks;

/** Maximum number of concurrent callback subscribers (Flutter engines). */
#define FLUTTER_EAP_MAX_SUBSCRIBERS 8

// =============================================================================
// Dart-facing exports (declared here, DEFINED by each fan-out bridge as thin
// wrappers over the flutter_eap_fanout_* functions below - the bridges keep
// their own context bookkeeping around the delegation)
// =============================================================================

/**
 * Register an ADDITIONAL callback subscriber (multi-engine fan-out).
 * Each subscriber receives every callback for which it registered a non-NULL
 * function pointer. Heap payloads (video frames, log / file-status strings,
 * suspend holder ids) are allocated per subscriber; each Dart side frees its
 * own copy with flutter_eap_free(). Calibration-result arrays are deep-copied
 * per subscriber slot and stay bridge-owned (freed on next dispatch or
 * removal), matching the existing Dart no-free semantics.
 * Installs the C adapters on the core client if not yet installed.
 *
 * @return handle > 0 on success; -1 on invalid args; -2 when the table is full.
 */
EAP_FANOUT_EXPORT int64_t flutter_eap_add_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks);

/**
 * flutter_eap_add_callbacks with an engine token for stale-subscriber reaping
 * (desktop). On platforms without host-side bookkeeping (no Kotlin plugin to
 * reap a hot-restarted engine's dead subscriber), the caller passes a stable
 * per-engine token (Dart: PlatformDispatcher.instance.engineId - it identifies
 * the ENGINE, not the isolate, so it survives a hot restart): a re-add with
 * the same non-zero token atomically replaces (reaps) the previous subscriber
 * carrying that token before adding. engine_token == 0 means "no token" and
 * behaves exactly like flutter_eap_add_callbacks (no reaping - Android keeps
 * its Kotlin reportSubscriberHandle mechanism instead).
 *
 * @return handle > 0 on success; -1 on invalid args; -2 when the table is full.
 */
EAP_FANOUT_EXPORT int64_t flutter_eap_add_callbacks_engine(eap_client* client, const flutter_eap_callbacks* callbacks, int64_t engine_token);

/**
 * Remove one callback subscriber. Idempotent: unknown or stale handles return
 * -1 and do nothing. After return (synchronized with dispatch via the module
 * mutex) the subscriber's function pointers can no longer be invoked - the safe
 * point for the owner to close its NativeCallables.
 * Does NOT unregister the C adapters from the core client, even when the table
 * empties - other engines may subscribe later.
 *
 * @return 0 on success, -1 if the handle was not found.
 */
EAP_FANOUT_EXPORT int flutter_eap_remove_callbacks(eap_client* client, int64_t handle);

// =============================================================================
// Module API (bridge-internal - NOT part of the Dart FFI surface)
// =============================================================================

/**
 * Table core of the add wrappers above: reap same-token slot(s) when
 * engine_token != 0, claim a free slot, install the core adapters (idempotent
 * eap_client_set_callbacks with the identical config). On adapter-install
 * failure the fresh slot is removed again and -1 is returned.
 */
int64_t flutter_eap_fanout_add(eap_client* client, const flutter_eap_callbacks* callbacks, int64_t engine_token);

/** Table core of flutter_eap_remove_callbacks. 0 on success, -1 not found. */
int flutter_eap_fanout_remove(int64_t handle);

/**
 * Legacy flutter_eap_set_callbacks semantics: clear the whole subscriber
 * table, register the caller as the only subscriber (slot 0), install the
 * core adapters. Preserves the pre-fan-out single-owner behavior for callers
 * that never migrated to add_callbacks. Returns 0 on success, else the
 * eap_client_set_callbacks error.
 */
int flutter_eap_fanout_set_single(eap_client* client, const flutter_eap_callbacks* callbacks);

/**
 * Legacy flutter_eap_clear_callbacks semantics: zero ALL subscriber slots
 * under the mutex (so any adapter currently dispatching observes the change
 * atomically), then unregister the C adapters from the core client so
 * eap_process_message does not even reach them. A later add/set call
 * re-registers the adapters.
 */
void flutter_eap_fanout_clear(eap_client* client);

/**
 * Fan a Skyle Link suspension change out to every registered subscriber's
 * on_suspend_state. Signature-compatible with the link glue's fan-out hook
 * (flutter_eap_link_glue_set_fanout_hook) - each bridge registers this
 * function at context creation. `holder` is valid only during the call; a
 * strdup'd copy is delivered per subscriber (each Dart isolate frees its own
 * via flutter_eap_free), same as the other string payloads.
 */
void flutter_eap_fanout_dispatch_suspend_state(bool suspended, const char* holder);

/**
 * Last error message captured by the module's on_error adapter, or NULL when
 * none was recorded yet. Backing storage for the bridges'
 * flutter_eap_get_last_error.
 */
const char* flutter_eap_fanout_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_EAP_FANOUT_H
