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
 *
 * Host state flow (HOST_STATE, spec section 8.2 - the hub-hosting app's
 * published UI state, e.g. menu bar / pointer overlay visibility): the cache
 * lives in skylelib's link client (per link, cleared when the link dies), so
 * this glue only adapts the change callback into the fan-out hook and
 * re-exports the getters for Dart seeding. When the supervisor leaves CLIENT
 * mode the glue fans out "unknown" (value_len -1) for every control it saw,
 * mirroring the stale-lease reset below. The hosting app (Skyle X) publishes
 * through flutter_skyle_link_publish_host_state.
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

/**
 * Multi-engine host-control fan-out hook: a HOST_CONTROL command (spec
 * section 8.1) received by the hub this process serves. `value` (NULL when
 * value_len is 0) and `sender_app_id` are valid only during the call (the
 * callee copies per subscriber). Fires synchronously within the hub event
 * callback - commands, not state: no cache, no lock, no mode-change reset.
 */
typedef void (*flutter_skyle_link_host_control_fanout_fn)(uint16_t control_id, const uint8_t* value, uint16_t value_len, const char* sender_app_id);

/** Register/replace the hook. Idempotent; NULL clears. */
void flutter_skyle_link_glue_set_host_control_fanout_hook(flutter_skyle_link_host_control_fanout_fn hook);

/**
 * Multi-engine link-client presence fan-out hook: a client connected to /
 * disconnected from the hub this process serves (the receiver's input for a
 * restore-on-disconnect policy keyed on app_id). `app_id` is valid only
 * during the call (the callee copies per subscriber); may be NULL.
 */
typedef void (*flutter_skyle_link_client_presence_fanout_fn)(bool connected, const char* app_id, int client_count);

/** Register/replace the hook. Idempotent; NULL clears. */
void flutter_skyle_link_glue_set_client_presence_fanout_hook(flutter_skyle_link_client_presence_fanout_fn hook);

/**
 * Multi-engine host-state fan-out hook: the hub-hosting app's published state
 * of one control changed (HOST_STATE, spec section 8.2; link CLIENT mode
 * only). `value` is valid only during the call (the callee copies per
 * subscriber); NULL when value_len <= 0. value_len -1 means the state became
 * unknown (link to the hub gone).
 */
typedef void (*flutter_skyle_link_host_state_fanout_fn)(uint16_t control_id, const uint8_t* value, int32_t value_len);

/** Register/replace the hook. Idempotent; NULL clears. */
void flutter_skyle_link_glue_set_host_state_fanout_hook(flutter_skyle_link_host_state_fanout_fn hook);

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
 *  - skyle_link_set_host_state_callback on `client`: the CLIENT-mode host
 *    state adapter (HOST_STATE changes -> host-state fan-out hook)
 *  - skyle_link_set_mode_callback: resets a stale cached suspension lease
 *    when the supervisor leaves a serving mode (OWNER/CLIENT) and reports
 *    every known host state as unknown when it leaves CLIENT mode
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
// Suspension + host state (the Skyle Link event surfaces above C)
// =============================================================================

/**
 * Request or release eye-control suspension (client mode only).
 * Returns skyle_result as int.
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_set_suspended(skyle_client* client, bool suspended);

/**
 * Fire-and-forget HOST_CONTROL command to the app hosting the hub (client
 * mode only; spec section 8.1): no reply, no lease, last writer wins at the
 * receiver, unknown control ids are ignored there. `value` layout is per
 * control id (skyle_link_host_control); may be NULL when value_len is 0.
 * Returns skyle_result as int.
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_send_host_control(skyle_client* client, uint16_t control_id, const uint8_t* value, uint16_t value_len);

/**
 * Read the cached suspension state (for Dart stream seeding). `holder_buf`
 * receives the holder app id as a NUL-terminated string (empty when not
 * suspended); pass at least SKYLE_LINK_MAX_APP_ID + 1 bytes.
 */
FLUTTER_SKYLE_LINK_EXPORT void flutter_skyle_get_suspension_state(bool* suspended, char* holder_buf, size_t buf_len);

/**
 * Last HOST_STATE value the hub-hosting app published for `control_id`, as
 * seen over the current local link (for Dart stream seeding). Copies up to
 * `value_cap` bytes into `value` and returns the full value length (>= 0), or
 * -1 when unknown: not a link client, nothing received yet, the hub predates
 * HOST_STATE (see flutter_skyle_link_get_hub_capabilities), or the link died.
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_get_host_state(skyle_client* client, uint16_t control_id, uint8_t* value, uint16_t value_cap);

/**
 * Visibility of a hub-hosting app overlay (SKYLE_LINK_CONTROL_MENU_BAR /
 * SKYLE_LINK_CONTROL_POINTER_OVERLAY) as last reported by that app:
 * 1 visible, 0 hidden, -1 unknown (same conditions as
 * flutter_skyle_link_get_host_state).
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_get_host_visibility(skyle_client* client, uint16_t control_id);

/**
 * Hosting-app side: publish the ACTUAL state of a control (re-export of
 * skyle_link_publish_host_state, spec section 8.2). Process-wide and mode
 * independent - stored, pushed into the hub while OWNER and seeded into
 * every later hub. Returns skyle_result as int.
 */
FLUTTER_SKYLE_LINK_EXPORT int flutter_skyle_link_publish_host_state(uint16_t control_id, const uint8_t* value, uint16_t value_len);

/**
 * HELLO_ACK capabilities (SKYLE_LINK_CAP_* bits) of the hub this process is
 * linked to; 0 when not a link client. Bit 1 (SKYLE_LINK_CAP_HOST_STATE)
 * tells "visibility not reported yet" from "this hub never reports it".
 */
FLUTTER_SKYLE_LINK_EXPORT uint32_t flutter_skyle_link_get_hub_capabilities(skyle_client* client);

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_SKYLE_LINK_GLUE_H
