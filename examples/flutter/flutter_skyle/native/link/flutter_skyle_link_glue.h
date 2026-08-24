/**
 * @file flutter_skyle_link_glue.h
 * @brief Shared Skyle Link glue for the flutter_skyle platform shims.
 *
 * Compiled into every platform's shim library (Android: libflutter_skyle.so via
 * android/CMakeLists.txt, iOS/macOS: the skylelib_unity.c unity include,
 * Windows: flutter_skyle_plugin.dll via windows/CMakeLists.txt) so that Dart
 * resolves ALL Skyle Link symbols from the same library it already opens for
 * the flutter_skyle_* API. This deliberately wraps the raw skyle_link_* /
 * skyle_hub_* SKYLELIB_API exports instead of binding them from Dart directly:
 *
 *  - The suspend holder string is valid only DURING the native callback.
 *    Dart NativeCallable.listener delivers asynchronously, so a C-side heap
 *    copy per delivery is mandatory - exactly like the existing logging /
 *    file-status adapters in the platform bridges.
 *  - On Apple platforms skylelib is a prebuilt STATIC library; referencing the
 *    link/hub symbols from this glue keeps them from being dead-stripped.
 *  - On Windows skylelib lives in a separate DLL that GetProcAddress on the
 *    plugin DLL would never search; the glue re-exports what Dart needs.
 *
 * Transport selection is fully automatic (spec section 10): the skylelib
 * supervisor owns the hub/local-link lifecycle. This glue only (a) installs
 * the process-wide event adapters once per client, (b) caches the suspension
 * state, and (c) re-exports the supervisor setters so Dart/Kotlin resolve
 * them from the flutter_skyle library on every platform.
 *
 * Suspension state flow (single source of truth: the cache in this file):
 *  - supervisor OWNER mode: skyle_link_set_supervisor_event_callback ->
 *    SUSPEND_CHANGED hub events
 *  - supervisor CLIENT mode: skyle_link_set_suspend_callback adapter
 * Both feed the cache and then fan out through the hook the platform bridges
 * register (flutter_skyle_fanout_dispatch_suspend_state on every fan-out
 * platform), delivering into each engine's subscriber slot. Dart seeds new
 * listeners from flutter_skyle_get_suspension_state.
 */

#ifndef FLUTTER_SKYLE_LINK_GLUE_H
#define FLUTTER_SKYLE_LINK_GLUE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <skylelib/skyle_client.h>

// Keep symbols reachable from Dart FFI (mirrors FLUTTER_SKYLE_EXPORT in the Apple
// bridge): `used` defeats -dead_strip, default visibility keeps them
// resolvable via DynamicLibrary.process() / dlsym. MSVC exports everything
// via WINDOWS_EXPORT_ALL_SYMBOLS.
#if defined(__GNUC__) || defined(__clang__)
#define FLUTTER_SKYLE_LINK_EXPORT __attribute__((used)) __attribute__((visibility("default")))
#else
#define FLUTTER_SKYLE_LINK_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Hook for the platform bridges (NOT exported to Dart)
// =============================================================================

/**
 * Multi-engine suspend fan-out hook. `holder` is valid only during the call
 * (the callee copies per subscriber); NULL when not suspended.
 */
typedef void (*flutter_skyle_link_suspend_fanout_fn)(bool suspended, const char* holder);

/** Register/replace the hook. Idempotent; NULL clears. */
void flutter_skyle_link_glue_set_fanout_hook(flutter_skyle_link_suspend_fanout_fn hook);

// =============================================================================
// Glue installation + automatic transport supervisor
// =============================================================================

/**
 * Install the glue's event adapters (idempotent, call once at client/context
 * creation - the Android bridge does it in get_or_create_context, Dart does
 * it right after obtaining the client pointer on the other platforms):
 *  - skyle_link_set_supervisor_event_callback: SUSPEND_CHANGED hub events
 *    while the supervisor is OWNER feed the suspension cache (other events
 *    are logged only)
 *  - skyle_link_set_suspend_callback on `client`: the CLIENT-mode suspension
 *    adapter (client-level setter, independent of any connect)
 *  - skyle_link_set_mode_callback: resets a stale cached suspension lease
 *    when the supervisor leaves a serving mode (OWNER/CLIENT)
 * The notice/closed client callbacks are deliberately NOT touched: skylelib
 * logs them itself and the single-slot registrations stay free for the
 * supervisor's own wiring.
 */
FLUTTER_SKYLE_LINK_EXPORT void flutter_skyle_link_glue_install(skyle_client* client);

/**
 * Identity used in HELLO / the hub config (re-export of
 * skyle_link_set_identity). May be called before or after client creation and
 * repeatedly - usb_capable flips when the platform USB permission changes.
 */
FLUTTER_SKYLE_LINK_EXPORT void flutter_skyle_set_identity(const char* app_id, uint8_t tier, bool usb_capable);

/**
 * Enable/disable the automatic transport supervisor (re-export of
 * skyle_link_set_supervisor_enabled). Enabling returns immediately; disabling
 * is a deliberate stop (OWNER sends BYE(handover) + releases USB, CLIENT
 * closes; no re-election until re-enabled).
 */
FLUTTER_SKYLE_LINK_EXPORT void flutter_skyle_set_supervisor_enabled(bool enabled);

/**
 * Current supervisor mode as int (skyle_link_supervisor_mode: 0 disabled,
 * 1 deciding, 2 owner, 3 client, 4 usb fallback).
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_get_supervisor_mode(void);

// =============================================================================
// Suspension (the only Skyle Link event surface above C)
// =============================================================================

/**
 * Request or release eye-control suspension (client mode only).
 * Returns skyle_result as int.
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_set_suspended(skyle_client* client, bool suspended);

/**
 * Read the cached suspension state (for Dart stream seeding). `holder_buf`
 * receives the holder app id as a NUL-terminated string (empty when not
 * suspended); pass at least SKYLE_LINK_MAX_APP_ID + 1 bytes.
 */
FLUTTER_SKYLE_LINK_EXPORT void flutter_skyle_get_suspension_state(bool* suspended, char* holder_buf, size_t buf_len);

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_SKYLE_LINK_GLUE_H
