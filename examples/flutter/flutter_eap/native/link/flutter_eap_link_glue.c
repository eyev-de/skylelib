/**
 * @file flutter_eap_link_glue.c
 * @brief Shared Skyle Link glue implementation (all platforms).
 *
 * See flutter_eap_link_glue.h for the architecture rationale. Everything in
 * here is platform-neutral C17; the only platform splits are logging and the
 * process-wide mutex.
 */

#include "flutter_eap_link_glue.h"

#include <skylelib/skyle_link.h>
#include <skylelib/skyle_hub.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// =============================================================================
// Platform shims: logging, mutex, strdup
// =============================================================================

// The Apple build pulls this file into skylelib_unity.c AFTER the platform
// bridge, which defines the same logging macros - redefine cleanly.
#undef LOG_TAG
#undef LOGD
#undef LOGE
#define LOG_TAG "FlutterEapLink"

#if defined(__ANDROID__)
#include <android/log.h>
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGD(...) do { fprintf(stderr, "[" LOG_TAG "] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
#define LOGE(...) do { fprintf(stderr, "[" LOG_TAG " ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
#endif

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
static SRWLOCK g_link_lock = SRWLOCK_INIT;
#define LINK_LOCK() AcquireSRWLockExclusive(&g_link_lock)
#define LINK_UNLOCK() ReleaseSRWLockExclusive(&g_link_lock)
#else
#include <pthread.h>
static pthread_mutex_t g_link_lock = PTHREAD_MUTEX_INITIALIZER;
#define LINK_LOCK() pthread_mutex_lock(&g_link_lock)
#define LINK_UNLOCK() pthread_mutex_unlock(&g_link_lock)
#endif

// =============================================================================
// Process-wide state (protected by g_link_lock unless noted)
// =============================================================================

// One-time adapter installation (flutter_eap_link_glue_install).
static bool g_glue_installed = false;

// Cached suspension state - the seed for Dart's currentSuspensionState.
static bool g_suspended = false;
static char g_holder[SKYLE_LINK_MAX_APP_ID + 1] = {0};

// Hook the platform bridges register (single writer at context creation,
// read from hub/link threads - plain pointer reads, same pattern as the
// Android bridge's g_host_owned flag). On every fan-out platform this is
// flutter_eap_fanout_dispatch_suspend_state, delivering the change into each
// engine's subscriber slot.
static flutter_eap_link_suspend_fanout_fn g_suspend_fanout = NULL;

void flutter_eap_link_glue_set_fanout_hook(flutter_eap_link_suspend_fanout_fn hook) {
    g_suspend_fanout = hook;
}

// =============================================================================
// Suspension cache + dispatch
// =============================================================================

/**
 * Update the cache and fan the change out. Called from hub event threads
 * (owner mode) and the link read thread (client mode). The holder string is
 * copied to the stack under the lock; dispatch happens outside the lock so a
 * callee can never deadlock against the cache.
 */
static void link_glue_update_suspension(bool suspended, const char* holder) {
    char holder_copy[SKYLE_LINK_MAX_APP_ID + 1];

    LINK_LOCK();
    g_suspended = suspended;
    if (suspended && holder) {
        strncpy(g_holder, holder, SKYLE_LINK_MAX_APP_ID);
        g_holder[SKYLE_LINK_MAX_APP_ID] = '\0';
    } else {
        g_holder[0] = '\0';
    }
    memcpy(holder_copy, g_holder, sizeof(holder_copy));
    LINK_UNLOCK();

    const char* effective = (suspended && holder_copy[0] != '\0') ? holder_copy : NULL;
    LOGD("suspension changed: suspended=%d holder=%s", suspended ? 1 : 0, effective ? effective : "(none)");

    // The fan-out hook copies the holder per subscriber; `effective` only has
    // to stay valid for the duration of the call.
    flutter_eap_link_suspend_fanout_fn fanout = g_suspend_fanout;
    if (fanout) {
        fanout(suspended, effective);
    }
}

void flutter_eap_get_suspension_state(bool* suspended, char* holder_buf, size_t buf_len) {
    LINK_LOCK();
    if (suspended) {
        *suspended = g_suspended;
    }
    if (holder_buf && buf_len > 0) {
        strncpy(holder_buf, g_holder, buf_len - 1);
        holder_buf[buf_len - 1] = '\0';
    }
    LINK_UNLOCK();
}

// =============================================================================
// Client-mode adapter (installed on the client by flutter_eap_link_glue_install)
// =============================================================================

static void link_glue_suspend_adapter(eap_client* client, bool suspended, const char* holder_app_id, void* user_data) {
    (void)client;
    (void)user_data;
    link_glue_update_suspension(suspended, holder_app_id);
}

// =============================================================================
// Hub event adapter (supervisor OWNER mode; registered process-wide via
// skyle_link_set_supervisor_event_callback). Only SUSPEND_CHANGED feeds the
// cache - everything else (client counts, preempt, errors) is handled by the
// supervisor itself and merely logged here.
// =============================================================================

static void link_glue_hub_event(const skyle_hub_event* event, void* user_data) {
    (void)user_data;
    if (!event) return;

    switch (event->type) {
        case SKYLE_HUB_EVENT_SUSPEND_CHANGED:
            link_glue_update_suspension(event->suspended, event->app_id);
            break;

        case SKYLE_HUB_EVENT_ERROR:
            LOGE("hub error: %s", event->message ? event->message : "(no message)");
            break;

        default:
            LOGD("hub event: type=%d count=%d tier=%u app=%s", (int)event->type, event->client_count,
                 (unsigned)event->tier, event->app_id ? event->app_id : "(unknown)");
            break;
    }
}

// =============================================================================
// Supervisor mode observer
// =============================================================================

/**
 * When the supervisor leaves a serving mode (OWNER: hub gone, lease died with
 * it; CLIENT: link to the hub gone, lease stale), a cached suspension can no
 * longer be trusted - report resumed. The next serving mode re-seeds the
 * cache (hub SUSPEND_CHANGED events, or the SUSPEND_STATE the hub sends right
 * after HELLO_ACK). Fires on the supervisor thread.
 */
static void link_glue_mode_changed(skyle_link_supervisor_mode old_mode, skyle_link_supervisor_mode new_mode, void* user_data) {
    (void)user_data;
    LOGD("supervisor mode: %d -> %d", (int)old_mode, (int)new_mode);

    bool left_serving = (old_mode == SKYLE_LINK_SUPERVISOR_OWNER || old_mode == SKYLE_LINK_SUPERVISOR_CLIENT) &&
                        (new_mode != SKYLE_LINK_SUPERVISOR_OWNER && new_mode != SKYLE_LINK_SUPERVISOR_CLIENT);
    if (!left_serving) {
        return;
    }

    bool was_suspended;
    LINK_LOCK();
    was_suspended = g_suspended;
    LINK_UNLOCK();
    if (was_suspended) {
        link_glue_update_suspension(false, NULL);
    }
}

// =============================================================================
// Glue installation + supervisor re-exports
// =============================================================================

void flutter_eap_link_glue_install(eap_client* client) {
    if (!client) {
        LOGE("glue_install: NULL client");
        return;
    }

    LINK_LOCK();
    bool already = g_glue_installed;
    g_glue_installed = true;
    LINK_UNLOCK();
    if (already) {
        return;
    }

    // Process-wide slots: hub events while the supervisor is OWNER, and the
    // mode observer for stale-lease cleanup. Registered outside the lock -
    // the setters are non-blocking but may fire callbacks that take it.
    skyle_link_set_supervisor_event_callback(link_glue_hub_event, NULL);
    skyle_link_set_mode_callback(link_glue_mode_changed, NULL);

    // Client-level CLIENT-mode suspension adapter. Independent of any connect:
    // installed once here, it fires whenever the supervisor runs a local link,
    // so the SUSPEND_STATE sent right after HELLO_ACK always seeds the cache.
    // The notice/closed slots stay untouched (skylelib logs them; the
    // supervisor may use them for its own re-election wiring).
    skyle_link_set_suspend_callback(client, link_glue_suspend_adapter, NULL);

    LOGD("glue_install: supervisor event + suspension adapters installed");
}

void flutter_eap_set_identity(const char* app_id, uint8_t tier, bool usb_capable) {
    skyle_link_set_identity(app_id, tier, usb_capable);
    LOGD("set_identity: app_id='%s' tier=%u usb_capable=%d", app_id ? app_id : "(null)", (unsigned)tier, usb_capable ? 1 : 0);
}

void flutter_eap_set_supervisor_enabled(bool enabled) {
    skyle_link_set_supervisor_enabled(enabled);
    LOGD("set_supervisor_enabled: %d", enabled ? 1 : 0);
}

int flutter_eap_get_supervisor_mode(void) {
    return (int)skyle_link_get_supervisor_mode();
}

// =============================================================================
// Suspension request (client mode)
// =============================================================================

int flutter_eap_link_set_suspended(eap_client* client, bool suspended) {
    if (!client) return -1;
    int result = (int)skyle_link_set_suspended(client, suspended);
    LOGD("link_set_suspended: %d -> %d", suspended ? 1 : 0, result);
    return result;
}
