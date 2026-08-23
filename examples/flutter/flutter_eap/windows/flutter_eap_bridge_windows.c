/**
 * @file flutter_eap_bridge_windows.c
 * @brief FFI bridge implementation for Windows
 *
 * Architecture:
 *
 * Windows: USB transport via USB bulk endpoints
 *   - C++ plugin calls flutter_eap_configure_usb_transport() for convenience
 *   - USB transport handles read/write/device_check entirely in C
 *
 * Dart Layer:
 *   - Each Flutter engine registers a subscriber via the shared multi-engine
 *     fan-out (flutter_eap_add_callbacks_engine, see
 *     native/fanout/flutter_eap_fanout.c) - main window + sub-windows all
 *     receive every callback independently
 *   - C library parses protocol and invokes the module's adapter callbacks
 *   - Adapters pass C structs by value to Dart
 *
 * Ported from flutter_eap_bridge_apple.c with these changes:
 *   - eap_transport_iokit -> eap_transport_usb
 *   - Removed iOS push-mode functions
 *   - Removed TARGET_OS_OSX/TARGET_OS_IOS guards
 */

#include "flutter_eap_bridge_windows.h"
#include "../native/link/flutter_eap_link_glue.h"  /* fan-out hook registration */
#include <eap_client.h>
#include <eap/eap_message_types.h>
#include <eap_transport_usb.h>
#include <skylelib/skyle_link.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#define LOG_TAG "FlutterEapBridge"
#define LOGD(...) do { fprintf(stderr, "[" LOG_TAG "] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define LOGE(...) do { fprintf(stderr, "[" LOG_TAG " ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)

/* =========================================================================
 * Internal structures and global state
 * ========================================================================= */

/* The Dart callback subscriber table (one slot per Flutter engine), the
 * C-to-Dart adapters, and the payload-copy rules live in the shared fan-out
 * module (native/fanout/flutter_eap_fanout.c) - this bridge keeps the WinUSB
 * transport/context specifics and delegates the callback machinery. */
typedef struct {
    eap_client* client;
    eap_transport_usb* usb_transport;
    uint16_t usb_vendor_id;   /* Remembered so the USB ownership callback can recreate */
    uint16_t usb_product_id;  /* the transport on reacquire (guarded by g_usb_transport_lock) */
} bridge_context;

static eap_client* g_client = NULL;
static bridge_context* g_context = NULL;

/* Guards the WinUSB transport lifecycle: flutter_eap_configure_usb_transport
 * runs on the Dart/platform thread while the Skyle Link USB ownership callback
 * fires on supervisor threads. SRWLOCK for static initialization. */
static SRWLOCK g_usb_transport_lock = SRWLOCK_INIT;
static bool g_usb_ownership_registered = false;

static bridge_context* get_context_for_client(eap_client* client) {
    if (!client) return NULL;
    if (g_client == client) return g_context;
    return NULL;
}

static void register_client_context(eap_client* client, bridge_context* ctx) {
    if (g_client != NULL) {
        LOGE("register_client_context: A client already exists! Only one client is allowed.");
        return;
    }
    g_client = client;
    g_context = ctx;
    LOGD("register_client_context: Registered client %p (context=%p)", client, ctx);
}

static void unregister_client_context(eap_client* client) {
    if (g_client == client) {
        LOGD("unregister_client_context: Unregistered client %p", client);
        g_client = NULL;
        g_context = NULL;
    } else {
        LOGE("unregister_client_context: Attempted to unregister client %p, but registered client is %p", client, g_client);
    }
}

/* =========================================================================
 * Public API Implementation
 * ========================================================================= */

static bridge_context* ensure_context(eap_client* client) {
    bridge_context* ctx = get_context_for_client(client);
    if (ctx) return ctx;

    ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
    if (!ctx) {
        LOGE("ensure_context: Failed to allocate context");
        return NULL;
    }
    ctx->client = client;
    ctx->usb_transport = NULL;
    /* Route the Skyle Link glue's suspension updates through the shared
     * fan-out (idempotent re-assignment; mirrors the Android bridge's
     * get_or_create_context). */
    flutter_eap_link_glue_set_fanout_hook(flutter_eap_fanout_dispatch_suspend_state);
    register_client_context(client, ctx);
    return ctx;
}

eap_client* flutter_eap_create_with_transport(void) {
    eap_client* client = eap_client_get_instance();
    if (!client) {
        LOGE("flutter_eap_create_with_transport: Failed to get client instance");
        return NULL;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return NULL;

    LOGD("flutter_eap_create_with_transport: Client ready (client=%p, ctx=%p)", client, ctx);
    return client;
}

bool flutter_eap_is_initialized(void) {
    return g_context != NULL;
}

eap_client* flutter_eap_get_instance(void) {
    return eap_client_get_instance();
}

int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks) {
    if (!client || !callbacks) {
        LOGE("flutter_eap_set_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    /* Legacy replace-all-with-one semantics (module: clear the whole
     * subscriber table, register the caller as the only subscriber). */
    int result = flutter_eap_fanout_set_single(client, callbacks);
    if (result != 0) {
        return result;
    }

    LOGD("flutter_eap_set_callbacks: Callbacks registered successfully for client %p (legacy single-subscriber mode)", client);
    return 0;
}

/* =========================================================================
 * Multi-engine subscriber fan-out (declared in flutter_eap_fanout.h)
 * ========================================================================= */

int64_t flutter_eap_add_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks) {
    return flutter_eap_add_callbacks_engine(client, callbacks, 0);
}

int64_t flutter_eap_add_callbacks_engine(eap_client* client, const flutter_eap_callbacks* callbacks, int64_t engine_token) {
    if (!client || !callbacks) {
        LOGE("flutter_eap_add_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    /* Table + adapter installation live in the shared fan-out module. A
     * re-add with the same non-zero engine token (Dart passes the native
     * engine id) reaps the previous subscriber first - the desktop
     * hot-restart path, where there is no Kotlin-style host bookkeeping. */
    int64_t handle = flutter_eap_fanout_add(client, callbacks, engine_token);
    if (handle == -2) {
        LOGE("flutter_eap_add_callbacks: Subscriber table full (%d slots)", FLUTTER_EAP_MAX_SUBSCRIBERS);
        return -2;
    }
    if (handle <= 0) {
        return -1;
    }

    LOGD("flutter_eap_add_callbacks: Registered subscriber handle=%lld for client %p (engine_token=%lld)",
         (long long)handle, (void*)client, (long long)engine_token);
    return handle;
}

int flutter_eap_remove_callbacks(eap_client* client, int64_t handle) {
    if (!client || handle <= 0) {
        return -1;
    }

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        return -1;
    }

    /* The module deliberately keeps the core adapters registered even when
     * the table empties - other engines may subscribe at any time. */
    int result = flutter_eap_fanout_remove(handle);
    LOGD("flutter_eap_remove_callbacks: handle=%lld -> %s", (long long)handle, result == 0 ? "removed" : "not found");
    return result;
}

/*
 * Create the WinUSB transport if absent (from the VID/PID stored in the
 * context) and register it on the client. Shared by the Dart-facing configure
 * call and the supervisor's USB ownership callback. Caller holds
 * g_usb_transport_lock.
 */
static int usb_register_transport_locked(bridge_context* ctx, eap_client* client) {
    if (!ctx->usb_transport) {
        eap_transport_usb_config config;
        memset(&config, 0, sizeof(config));
        config.vendor_id = ctx->usb_vendor_id;
        config.product_id = ctx->usb_product_id;
        config.timeout_ms = 1000;
        config.verbose = false;
        ctx->usb_transport = eap_transport_usb_create(&config);
        if (!ctx->usb_transport) {
            LOGD("usb_register_transport: Device not present yet, transport will connect when available");
        }
    }

    eap_transport_config transport_config;
    memset(&transport_config, 0, sizeof(transport_config));
    transport_config.transport_write = eap_transport_usb_write;
    transport_config.transport_read = eap_transport_usb_read;
    transport_config.usb_device_check = eap_transport_usb_get_check_callback();
    transport_config.transport_user_data = ctx->usb_transport;
    transport_config.connect_timeout_ms = 10000;
    transport_config.reconnect_interval_ms = 1000;
    transport_config.verbose = false;

    eap_result result = eap_client_set_transport(client, &transport_config);
    if (result != EAP_OK) {
        LOGE("usb_register_transport: eap_client_set_transport failed (%d)", result);
        return (int)result;
    }
    return 0;
}

/*
 * Skyle Link supervisor USB ownership hook. With this callback registered the
 * PLATFORM owns the transport lifecycle: the supervisor never snapshots or
 * restores a transport config itself. Contract (skyle_link.h /
 * skyle_link_supervisor.c):
 *  - cb(true) fires when ownership is acquired, BEFORE anything else touches
 *    the transport: (re)create the WinUSB transport and register it (which
 *    also restarts the background threads).
 *  - cb(false) fires AFTER the supervisor stopped the client's USB threads
 *    (hub stop + disconnect): destroy the transport, closing the WinUSB
 *    device handle/interface claim so the new owner can claim the device.
 * Fires on supervisor threads - non-blocking apart from bounded synchronous
 * WinUSB/SetupAPI calls. Idempotent: cb(true) reuses a still-live transport
 * (initial acquire right after configure), cb(false) with no transport is a
 * no-op. Resolves client/context via the globals: flutter_eap_destroy joins
 * the supervisor (inside eap_client_destroy) before freeing the context, so a
 * late fire sees NULL and does nothing.
 */
static void usb_ownership_callback(bool usb_wanted, void* user_data) {
    (void)user_data;
    eap_client* client = g_client;
    bridge_context* ctx = g_context;
    if (!client || !ctx) {
        LOGD("usb_ownership_callback: No client/context (usb_wanted=%d), ignoring", usb_wanted ? 1 : 0);
        return;
    }
    AcquireSRWLockExclusive(&g_usb_transport_lock);
    if (usb_wanted) {
        int result = usb_register_transport_locked(ctx, client);
        LOGD("usb_ownership_callback: USB acquired, transport %s (VID=0x%04X, PID=0x%04X, result=%d)",
             ctx->usb_transport ? "registered" : "pending device", ctx->usb_vendor_id, ctx->usb_product_id, result);
    } else {
        if (ctx->usb_transport) {
            eap_transport_usb_destroy(ctx->usb_transport);
            ctx->usb_transport = NULL;
            LOGD("usb_ownership_callback: USB released, WinUSB device claim closed");
        } else {
            LOGD("usb_ownership_callback: USB released, no transport to close");
        }
    }
    ReleaseSRWLockExclusive(&g_usb_transport_lock);
}

int flutter_eap_configure_usb_transport(eap_client* client, uint16_t vendor_id, uint16_t product_id) {
    if (!client) {
        LOGE("flutter_eap_configure_usb_transport: NULL client");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    AcquireSRWLockExclusive(&g_usb_transport_lock);

    /* Destroy existing USB transport if any (reconfigure replaces it) */
    if (ctx->usb_transport) {
        eap_transport_usb_destroy(ctx->usb_transport);
        ctx->usb_transport = NULL;
    }
    ctx->usb_vendor_id = vendor_id;
    ctx->usb_product_id = product_id;

    int result = usb_register_transport_locked(ctx, client);

    /* First configure: hand the transport lifecycle to the platform layer for
     * Skyle Link handovers. */
    if (result == 0 && !g_usb_ownership_registered) {
        skyle_link_set_usb_ownership_callback(usb_ownership_callback, NULL);
        g_usb_ownership_registered = true;
        LOGD("flutter_eap_configure_usb_transport: USB ownership callback registered");
    }

    ReleaseSRWLockExclusive(&g_usb_transport_lock);

    if (result != 0) {
        return result;
    }

    LOGD("flutter_eap_configure_usb_transport: USB transport configured (VID=0x%04X, PID=0x%04X)", vendor_id, product_id);
    return 0;
}

void flutter_eap_clear_callbacks(eap_client* client) {
    if (!client) return;

    LOGD("flutter_eap_clear_callbacks: Clearing callbacks for client %p", client);

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGD("flutter_eap_clear_callbacks: No context found, nothing to clear");
        return;
    }

    /* Module: zero ALL subscriber slots under the mutex (atomic for any
     * adapter currently dispatching), then unregister the C adapters from
     * eap_client so eap_process_message does not even reach them.
     * Belt-and-suspenders against the case where a Dart NativeCallable has
     * been closed without its destroy() running - e.g. plugin teardown racing
     * with an in-flight WinUSB read. A later set/add call re-registers the
     * adapters. */
    flutter_eap_fanout_clear(client);

    LOGD("flutter_eap_clear_callbacks: Callbacks cleared successfully");
}

void flutter_eap_destroy(eap_client* client) {
    if (!client) return;

    LOGD("flutter_eap_destroy: Starting destruction for client %p", client);

    /* Clear Dart callbacks first to prevent any stray invocations */
    flutter_eap_clear_callbacks(client);

    bridge_context* ctx = get_context_for_client(client);

    /* Also clear the C-level adapter callbacks before destroying
     * (safe since we're about to stop all threads anyway) */
    eap_callback_config empty_config = {0};
    eap_client_set_callbacks(client, &empty_config);

    /* Destroy client (this stops background thread and waits for it; it also
     * joins the Skyle Link supervisor first, so the USB ownership callback
     * cannot fire past this point) */
    eap_client_destroy(client);

    /* Drop the ownership registration so a future create/configure cycle
     * starts clean (the supervisor is already stopped and joined above). */
    AcquireSRWLockExclusive(&g_usb_transport_lock);
    if (g_usb_ownership_registered) {
        skyle_link_set_usb_ownership_callback(NULL, NULL);
        g_usb_ownership_registered = false;
    }
    if (ctx && ctx->usb_transport) {
        eap_transport_usb_destroy(ctx->usb_transport);
        ctx->usb_transport = NULL;
    }
    ReleaseSRWLockExclusive(&g_usb_transport_lock);

    unregister_client_context(client);

    if (ctx) {
        free(ctx);
    }

    LOGD("flutter_eap_destroy: Client destroyed");
}

int flutter_eap_connect(eap_client* client) {
    if (!client) return -1;

    eap_connection_state current_state = eap_client_get_state(client);
    LOGD("flutter_eap_connect: Current state: %d", (int)current_state);

    // While the transport supervisor runs, a Dart-initiated connect must never
    // force-reset the link (it would kill a healthy local link or a
    // supervisor-managed USB session); eap_client_connect is a kick then.
    if (current_state != EAP_STATE_DISCONNECTED && !skyle_link_supervisor_is_enabled()) {
        LOGD("flutter_eap_connect: Client not in DISCONNECTED state (%d), resetting...", (int)current_state);
        eap_client_disconnect(client);
    }

    eap_result result = eap_client_connect(client);
    if (result != EAP_OK) {
        LOGE("flutter_eap_connect: Connect failed (%d)", result);
        return result;
    }

    LOGD("flutter_eap_connect: Connected - background thread handles all I/O automatically");
    return 0;
}

int flutter_eap_disconnect(eap_client* client) {
    if (!client) return -1;

    /* Only stop background thread if running */
    if (eap_client_is_background_running(client)) {
        eap_result bg_result = eap_client_stop_background(client);
        if (bg_result != EAP_OK) {
            LOGD("flutter_eap_disconnect: Background thread stop result: %d", bg_result);
        }
    }

    eap_result result = eap_client_disconnect(client);
    LOGD("flutter_eap_disconnect: Disconnected");
    return result;
}

int flutter_eap_enable_gaze(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_gaze(client, enable);
    LOGD("flutter_eap_enable_gaze: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_enable_positioning(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_positioning(client, enable);
    LOGD("flutter_eap_enable_positioning: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_request_version(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_request_version(client);
    LOGD("flutter_eap_request_version: Requested (%d)", result);
    return result;
}

int flutter_eap_enable_control(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_control(client, enable);
    LOGD("flutter_eap_enable_control: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_send_control(eap_client* client, const eap_control_message* message) {
    if (!client) return -1;
    eap_result result = eap_client_send_control(client, message);
    LOGD("flutter_eap_send_control: (%d)", result);
    return result;
}

int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info) {
    if (!client || !info) return -1;
    eap_result result = eap_client_send_display_info(client, info);
    LOGD("flutter_eap_send_display_info: %ux%upx %.1fx%.1fmm (%d)",
         info->resolution.width, info->resolution.height,
         info->size_mm.width, info->size_mm.height, result);
    return result;
}

int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config) {
    if (!client) return -1;
    eap_result result = eap_client_start_calibration(client, config);
    LOGD("flutter_eap_start_calibration: (%d)", result);
    return result;
}

int flutter_eap_collect_calibration_points(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_collect_calibration_points(client);
    LOGD("flutter_eap_collect_calibration_points: (%d)", result);
    return result;
}

int flutter_eap_abort_calibration(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_abort_calibration(client);
    LOGD("flutter_eap_abort_calibration: (%d)", result);
    return result;
}

int flutter_eap_enable_video(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_video(client, enable);
    LOGD("flutter_eap_enable_video: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_enable_logging(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_logging(client, enable);
    LOGD("flutter_eap_enable_logging: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

int flutter_eap_get_state(eap_client* client) {
    if (!client) return -1;
    return (int)eap_client_get_state(client);
}

const char* flutter_eap_get_last_error(eap_client* client) {
    if (!client) return NULL;
    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) return NULL;
    /* The error buffer lives in the fan-out module (its on_error adapter
     * records the message before dispatching to the subscribers). */
    return flutter_eap_fanout_last_error();
}

/* =========================================================================
 * File Transfer Functions
 * ========================================================================= */

int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash) {
    if (!client || !path || !data) return -1;
    eap_result result = eap_client_upload_file(client, path, data, data_len, sha256_hash);
    LOGD("flutter_eap_upload_file: path=%s, size=%u (%d)", path, data_len, result);
    return result;
}

int flutter_eap_cancel_upload(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_cancel_upload(client);
    LOGD("flutter_eap_cancel_upload: (%d)", result);
    return result;
}

void flutter_eap_free(void* ptr) {
    free(ptr);
}
