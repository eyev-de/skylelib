/**
 * @file flutter_skyle_bridge_apple.c
 * @brief FFI bridge implementation for Apple platforms (iOS/macOS)
 *
 * Architecture:
 *
 * iOS: Swift provides transport via ExternalAccessory (EASession)
 *   - Swift calls flutter_skyle_set_apple_transport() with C function pointers
 *   - C background thread calls transport_read/write via those function pointers
 *
 * macOS: IOKit provides transport via USB bulk endpoints
 *   - Swift calls flutter_skyle_configure_iokit_transport() for convenience
 *   - IOKit transport handles read/write/device_check entirely in C
 *
 * Dart Layer:
 *   - macOS: each Flutter engine registers a subscriber via the shared
 *     multi-engine fan-out (flutter_skyle_add_callbacks_engine, see
 *     native/fanout/flutter_skyle_fanout.c) - main window + sub-windows all
 *     receive every callback independently
 *   - iOS: single-slot flutter_skyle_set_callbacks() (one engine, push mode)
 *   - C library parses protocol and invokes adapter callbacks
 *   - Adapters pass C structs by value to Dart
 */

#include "flutter_skyle_bridge_apple.h"
#include <skylelib/skyle_client.h>
#include <skylelib/messages/skyle_message_types.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <TargetConditionals.h>

// skyle_link.h is platform-neutral (flutter_skyle_connect consults the
// supervisor on both platforms); the IOKit transport and the fan-out hook
// wiring are macOS-only.
#include <skylelib/skyle_link.h>

#if TARGET_OS_OSX
#include <skylelib/skyle_transport_iokit.h>
#include "../../native/link/flutter_skyle_link_glue.h"  // fan-out hook registration
#endif

#define LOG_TAG "FlutterSkyleBridge"
#define LOGD(...) do { fprintf(stderr, "[" LOG_TAG "] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define LOGE(...) do { fprintf(stderr, "[" LOG_TAG " ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)

// =============================================================================
// Internal structures and global state
// =============================================================================

typedef struct {
#if TARGET_OS_IOS
    // iOS single-slot callback machinery. On macOS the subscriber table, the
    // adapters, and the calibration deep copies live in the shared fan-out
    // module (native/fanout/flutter_skyle_fanout.c).
    flutter_skyle_callbacks dart_callbacks;
    pthread_mutex_t callback_mutex;  // Protects dart_callbacks against dispatch thread race
    char last_error[256];
    // Deep copies of calibration result arrays kept alive for async Dart callback
    skyle_quality_point* calib_left_copy;
    skyle_quality_point* calib_right_copy;
#endif
    skyle_client* client;
#if TARGET_OS_OSX
    skyle_transport_iokit* iokit_transport;
    uint16_t iokit_vendor_id;   // Remembered so the USB ownership callback can recreate
    uint16_t iokit_product_id;  // the transport on reacquire (guarded by g_iokit_mutex)
#endif
} bridge_context;

static skyle_client* g_client = NULL;
static bridge_context* g_context = NULL;

#if TARGET_OS_OSX
// Guards the IOKit transport lifecycle: flutter_skyle_configure_iokit_transport
// runs on the Dart/platform thread while the Skyle Link USB ownership callback
// fires on supervisor threads.
static pthread_mutex_t g_iokit_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_usb_ownership_registered = false;
#endif

static bridge_context* get_context_for_client(skyle_client* client) {
    if (!client) {
        LOGE("get_context_for_client: NULL client pointer");
        return NULL;
    }
    if (g_client == client) {
        return g_context;
    }
    LOGE("get_context_for_client: No context found for client %p", client);
    return NULL;
}

static void register_client_context(skyle_client* client, bridge_context* ctx) {
    if (g_client != NULL) {
        LOGE("register_client_context: A client already exists! Only one client is allowed.");
        return;
    }
    g_client = client;
    g_context = ctx;
    LOGD("register_client_context: Registered client %p (context=%p)", client, ctx);
}

static void unregister_client_context(skyle_client* client) {
    if (g_client == client) {
        LOGD("unregister_client_context: Unregistered client %p", client);
        g_client = NULL;
        g_context = NULL;
    } else {
        LOGE("unregister_client_context: Attempted to unregister client %p, but registered client is %p", client, g_client);
    }
}

#if TARGET_OS_IOS
// =============================================================================
// C-to-Dart callback adapters (iOS single-slot; the fan-out platforms use the
// shared module's adapters instead)
// =============================================================================

static void on_gaze_adapter(skyle_client* client, const skyle_gaze_response* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_gaze) {
        ctx->dart_callbacks.on_gaze(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_positioning_adapter(skyle_client* client, const skyle_positioning_response* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_positioning) {
        ctx->dart_callbacks.on_positioning(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_version_adapter(skyle_client* client, const skyle_version_response* version, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !version) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_version) {
        ctx->dart_callbacks.on_version(*version, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_control_adapter(skyle_client* client, const skyle_control_message* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_control) {
        ctx->dart_callbacks.on_control(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_point_adapter(skyle_client* client, const skyle_next_calibration_point* point, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !point) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_point) {
        ctx->dart_callbacks.on_calibration_point(*point, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_progress_adapter(skyle_client* client, const skyle_collecting_calibration_points* progress, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !progress) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_progress) {
        ctx->dart_callbacks.on_calibration_progress(*progress, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_paused_adapter(skyle_client* client, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_paused) {
        ctx->dart_callbacks.on_calibration_paused(ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_finished_adapter(skyle_client* client, const skyle_finished_calibration* result, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !result) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_finished) {
        // Deep copy quality point arrays - NativeCallable.listener is async,
        // so the original arrays will be freed before Dart processes the callback.
        free(ctx->calib_left_copy);
        free(ctx->calib_right_copy);
        ctx->calib_left_copy = NULL;
        ctx->calib_right_copy = NULL;

        skyle_finished_calibration copy = *result;

        if (result->left_count > 0 && result->left) {
            size_t left_size = result->left_count * sizeof(skyle_quality_point);
            ctx->calib_left_copy = (skyle_quality_point*)malloc(left_size);
            if (ctx->calib_left_copy) {
                memcpy(ctx->calib_left_copy, result->left, left_size);
                copy.left = ctx->calib_left_copy;
            }
        }

        if (result->right_count > 0 && result->right) {
            size_t right_size = result->right_count * sizeof(skyle_quality_point);
            ctx->calib_right_copy = (skyle_quality_point*)malloc(right_size);
            if (ctx->calib_right_copy) {
                memcpy(ctx->calib_right_copy, result->right, right_size);
                copy.right = ctx->calib_right_copy;
            }
        }

        ctx->dart_callbacks.on_calibration_finished(copy, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_state_change_adapter(skyle_client* client, skyle_connection_state old_state,
                                    skyle_connection_state new_state, void* user_data) {
    (void)client;
    (void)old_state;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_state_change) {
        ctx->dart_callbacks.on_state_change((int)new_state, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_error_adapter(skyle_client* client, skyle_result error, const char* message, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !message) return;

    LOGE("on_error_adapter: Error code=%d, message='%s'", (int)error, message);
    strncpy(ctx->last_error, message, sizeof(ctx->last_error) - 1);
    ctx->last_error[sizeof(ctx->last_error) - 1] = '\0';

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_error) {
        ctx->dart_callbacks.on_error(message, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_video_adapter(skyle_client* client, const skyle_video_response* video,
                              void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !video || !video->pixel_data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_video) {
        // Convert to RGBA in C (compiler auto-vectorises) so Dart receives
        // ready-to-display pixels with no per-pixel loop on the UI thread.
        // The heap-allocated buffer is owned by Dart (freed via NativeFinalizer).
        const uint32_t pixel_count = (uint32_t)video->width * (uint32_t)video->height;
        // Use uint64_t to detect overflow before casting: pixel_count * 4 can
        // silently overflow uint32_t when width/height contain garbage values
        // from a corrupted or partially-assembled frame (e.g. during shutdown).
        // 64 MB is a generous upper bound (640x480 RGBA = ~1.2 MB).
        const uint64_t rgba_size_64 = (uint64_t)pixel_count * 4;
        if (pixel_count == 0 || rgba_size_64 > (64u * 1024u * 1024u)) {
            pthread_mutex_unlock(&ctx->callback_mutex);
            return;
        }
        const uint32_t rgba_size = (uint32_t)rgba_size_64;
        uint8_t* rgba = (uint8_t*)malloc(rgba_size);
        if (rgba) {
            const uint8_t* src = video->pixel_data;
            switch (video->channels) {
                case 1: // Grayscale -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        const uint8_t v = src[i];
                        rgba[i * 4]     = v;
                        rgba[i * 4 + 1] = v;
                        rgba[i * 4 + 2] = v;
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
                case 3: // BGR -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        rgba[i * 4]     = src[i * 3 + 2];
                        rgba[i * 4 + 1] = src[i * 3 + 1];
                        rgba[i * 4 + 2] = src[i * 3];
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
                case 4: // BGRA -> RGBA
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        rgba[i * 4]     = src[i * 4 + 2];
                        rgba[i * 4 + 1] = src[i * 4 + 1];
                        rgba[i * 4 + 2] = src[i * 4];
                        rgba[i * 4 + 3] = src[i * 4 + 3];
                    }
                    break;
                default: // Fallback: treat as grayscale
                    for (uint32_t i = 0; i < pixel_count; i++) {
                        const uint8_t v = src[i % video->pixel_data_length];
                        rgba[i * 4]     = v;
                        rgba[i * 4 + 1] = v;
                        rgba[i * 4 + 2] = v;
                        rgba[i * 4 + 3] = 255;
                    }
                    break;
            }
            ctx->dart_callbacks.on_video(rgba, rgba_size,
                                         video->width, video->height, 4,
                                         ctx->dart_callbacks.user_data);
        }
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_file_status_adapter(skyle_client* client,
    const skyle_file_status_response* status, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !status) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_file_status) {
        // NativeCallable.listener posts to a Dart port — the callback runs
        // asynchronously. The error_message pointer must survive until Dart
        // reads it, so heap-allocate a copy. Dart frees it after reading.
        char* error_msg = NULL;
        if (status->status == SKYLE_FILE_STATUS_FAILED && status->error_message[0] != '\0') {
            error_msg = strdup(status->error_message);
        }
        ctx->dart_callbacks.on_file_status(
            (uint16_t)status->status,
            status->progress,
            error_msg,
            ctx->dart_callbacks.user_data
        );
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_logging_adapter(skyle_client* client,
    const skyle_logging_response* log, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !log) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_logging) {
        // strdup so the message survives the async hop to Dart via
        // NativeCallable.listener; Dart frees with flutter_skyle_free.
        char* msg = (log->message_len > 0) ? strdup(log->message) : NULL;
        ctx->dart_callbacks.on_logging(
            (uint8_t)log->level,
            msg,
            log->header.timestamp_ms,
            ctx->dart_callbacks.user_data
        );
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}
#endif // TARGET_OS_IOS

// =============================================================================
// Public API Implementation
// =============================================================================

static bridge_context* ensure_context(skyle_client* client) {
    bridge_context* ctx = get_context_for_client(client);
    if (ctx) return ctx;

    ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
    if (!ctx) {
        LOGE("ensure_context: Failed to allocate context");
        return NULL;
    }
#if TARGET_OS_IOS
    pthread_mutex_init(&ctx->callback_mutex, NULL);
    ctx->calib_left_copy = NULL;
    ctx->calib_right_copy = NULL;
#endif
    ctx->client = client;
#if TARGET_OS_OSX
    ctx->iokit_transport = NULL;
    // Route the Skyle Link glue's suspension updates through the shared
    // fan-out (idempotent re-assignment; mirrors the Android bridge's
    // get_or_create_context).
    flutter_skyle_link_glue_set_fanout_hook(flutter_skyle_fanout_dispatch_suspend_state);
#endif
    register_client_context(client, ctx);
    return ctx;
}

FLUTTER_SKYLE_EXPORT skyle_client* flutter_skyle_create_with_transport(void) {
    skyle_client* client = skyle_client_get_instance();
    if (!client) {
        LOGE("flutter_skyle_create_with_transport: Failed to get client instance");
        return NULL;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return NULL;

    LOGD("flutter_skyle_create_with_transport: Client ready (client=%p, ctx=%p)", client, ctx);
    return client;
}

FLUTTER_SKYLE_EXPORT bool flutter_skyle_is_initialized(void) {
    return g_context != NULL;
}

FLUTTER_SKYLE_EXPORT skyle_client* flutter_skyle_get_instance(void) {
    return skyle_client_get_instance();
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_set_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks) {
    if (!client || !callbacks) {
        LOGE("flutter_skyle_set_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

#if TARGET_OS_OSX
    // Legacy replace-all-with-one semantics (module: clear the whole
    // subscriber table, register the caller as the only subscriber).
    int result = flutter_skyle_fanout_set_single(client, callbacks);
    if (result != 0) {
        return result;
    }

    LOGD("flutter_skyle_set_callbacks: Callbacks registered successfully for client %p (legacy single-subscriber mode)", client);
    return 0;
#else
    // Mutex-protected for hot restart safety
    pthread_mutex_lock(&ctx->callback_mutex);
    memcpy(&ctx->dart_callbacks, callbacks, sizeof(flutter_skyle_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    skyle_callback_config callback_config = {
        .on_gaze = on_gaze_adapter,
        .on_positioning = on_positioning_adapter,
        .on_version = on_version_adapter,
        .on_control = on_control_adapter,
        .on_calibration_point = on_calibration_point_adapter,
        .on_calibration_progress = on_calibration_progress_adapter,
        .on_calibration_paused = on_calibration_paused_adapter,
        .on_calibration_finished = on_calibration_finished_adapter,
        .on_video = on_video_adapter,
        .on_file_status = on_file_status_adapter,
        .on_logging = on_logging_adapter,
        .on_state_change = on_state_change_adapter,
        .on_error = on_error_adapter,
        .user_data = ctx
    };

    skyle_result result = skyle_client_set_callbacks(client, &callback_config);
    if (result != SKYLE_OK) {
        LOGE("flutter_skyle_set_callbacks: skyle_client_set_callbacks failed (%d)", result);
        return (int)result;
    }

    LOGD("flutter_skyle_set_callbacks: Callbacks registered successfully for client %p", client);
    return 0;
#endif
}

#if TARGET_OS_OSX
// =============================================================================
// Multi-engine subscriber fan-out (macOS; declared in flutter_skyle_fanout.h)
// =============================================================================

FLUTTER_SKYLE_EXPORT int64_t flutter_skyle_add_callbacks(skyle_client* client, const flutter_skyle_callbacks* callbacks) {
    return flutter_skyle_add_callbacks_engine(client, callbacks, 0);
}

FLUTTER_SKYLE_EXPORT int64_t flutter_skyle_add_callbacks_engine(skyle_client* client, const flutter_skyle_callbacks* callbacks, int64_t engine_token) {
    if (!client || !callbacks) {
        LOGE("flutter_skyle_add_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    // Table + adapter installation live in the shared fan-out module. A
    // re-add with the same non-zero engine token (Dart passes the native
    // engine id) reaps the previous subscriber first - the desktop
    // hot-restart path, where there is no Kotlin-style host bookkeeping.
    int64_t handle = flutter_skyle_fanout_add(client, callbacks, engine_token);
    if (handle == -2) {
        LOGE("flutter_skyle_add_callbacks: Subscriber table full (%d slots)", FLUTTER_SKYLE_MAX_SUBSCRIBERS);
        return -2;
    }
    if (handle <= 0) {
        return -1;
    }

    LOGD("flutter_skyle_add_callbacks: Registered subscriber handle=%lld for client %p (engine_token=%lld)",
         (long long)handle, (void*)client, (long long)engine_token);
    return handle;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_remove_callbacks(skyle_client* client, int64_t handle) {
    if (!client || handle <= 0) {
        return -1;
    }

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        return -1;
    }

    // The module deliberately keeps the core adapters registered even when
    // the table empties - other engines may subscribe at any time.
    int result = flutter_skyle_fanout_remove(handle);
    LOGD("flutter_skyle_remove_callbacks: handle=%lld -> %s", (long long)handle, result == 0 ? "removed" : "not found");
    return result;
}
#endif // TARGET_OS_OSX

FLUTTER_SKYLE_EXPORT void flutter_skyle_set_apple_transport(
    skyle_client* client,
    skyle_transport_read_fn read_fn,
    skyle_transport_write_fn write_fn,
    skyle_usb_device_check_fn device_check_fn,
    void* user_data
) {
    if (!client) {
        LOGE("flutter_skyle_set_apple_transport: NULL client");
        return;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return;

    skyle_transport_config transport_config = {
        .transport_write = write_fn,
        .transport_read = read_fn,
        .usb_device_check = device_check_fn,
        .transport_user_data = user_data,
        .connect_timeout_ms = 10000,
        .reconnect_interval_ms = 1000,
        .verbose = false
    };

    skyle_result result = skyle_client_set_transport(client, &transport_config);
    if (result != SKYLE_OK) {
        LOGE("flutter_skyle_set_apple_transport: skyle_client_set_transport failed (%d)", result);
        return;
    }

    LOGD("flutter_skyle_set_apple_transport: Transport configured successfully");
}

#if TARGET_OS_OSX
/**
 * Create the IOKit transport if absent (from the VID/PID stored in the
 * context) and register it on the client. Shared by the Dart-facing configure
 * call and the supervisor's USB ownership callback. Caller holds g_iokit_mutex.
 */
static int iokit_register_transport_locked(bridge_context* ctx, skyle_client* client) {
    if (!ctx->iokit_transport) {
        skyle_transport_iokit_config iokit_config = {
            .vendor_id = ctx->iokit_vendor_id,
            .product_id = ctx->iokit_product_id,
            .timeout_ms = 1000,
            .verbose = false
        };
        ctx->iokit_transport = skyle_transport_iokit_create(&iokit_config);
        if (!ctx->iokit_transport) {
            LOGD("iokit_register_transport: Device not present yet, transport will connect when available");
        }
    }

    // Set transport using IOKit functions
    skyle_transport_config transport_config = {
        .transport_write = skyle_transport_iokit_write,
        .transport_read = skyle_transport_iokit_read,
        .usb_device_check = skyle_transport_iokit_get_check_callback(),
        .transport_user_data = ctx->iokit_transport,
        .connect_timeout_ms = 10000,
        .reconnect_interval_ms = 1000,
        .verbose = false
    };

    skyle_result result = skyle_client_set_transport(client, &transport_config);
    if (result != SKYLE_OK) {
        LOGE("iokit_register_transport: skyle_client_set_transport failed (%d)", result);
        return (int)result;
    }
    return 0;
}

/**
 * Skyle Link supervisor USB ownership hook (macOS only). With this callback
 * registered the PLATFORM owns the transport lifecycle: the supervisor never
 * snapshots/restores a transport config itself. Contract (skyle_link.h /
 * skyle_link_supervisor.c):
 *  - cb(true) fires when ownership is acquired, BEFORE anything else touches
 *    the transport: (re)create the IOKit transport and register it (which
 *    also restarts the background threads).
 *  - cb(false) fires AFTER the supervisor stopped the client's USB threads
 *    (hub stop + disconnect): destroy the transport, closing the IOKit
 *    device/interface claim so the new owner can claim the device.
 * Fires on supervisor threads - non-blocking apart from bounded synchronous
 * IOKit calls (skyle_transport_iokit_create/destroy are runloop-free and safe
 * off the main thread). Idempotent: cb(true) reuses a still-live transport
 * (initial acquire right after configure), cb(false) with no transport is a
 * no-op. Resolves client/context via the globals: flutter_skyle_destroy joins
 * the supervisor (inside skyle_client_destroy) before freeing the context, so a
 * late fire sees NULL and does nothing.
 */
static void iokit_usb_ownership_callback(bool usb_wanted, void* user_data) {
    (void)user_data;
    skyle_client* client = g_client;
    bridge_context* ctx = g_context;
    if (!client || !ctx) {
        LOGD("iokit_usb_ownership_callback: No client/context (usb_wanted=%d), ignoring", usb_wanted ? 1 : 0);
        return;
    }
    pthread_mutex_lock(&g_iokit_mutex);
    if (usb_wanted) {
        int result = iokit_register_transport_locked(ctx, client);
        LOGD("iokit_usb_ownership_callback: USB acquired, transport %s (VID=0x%04X, PID=0x%04X, result=%d)",
             ctx->iokit_transport ? "registered" : "pending device", ctx->iokit_vendor_id, ctx->iokit_product_id, result);
    } else {
        if (ctx->iokit_transport) {
            skyle_transport_iokit_destroy(ctx->iokit_transport);
            ctx->iokit_transport = NULL;
            LOGD("iokit_usb_ownership_callback: USB released, IOKit device claim closed");
        } else {
            LOGD("iokit_usb_ownership_callback: USB released, no transport to close");
        }
    }
    pthread_mutex_unlock(&g_iokit_mutex);
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_configure_iokit_transport(skyle_client* client, uint16_t vendor_id, uint16_t product_id) {
    if (!client) {
        LOGE("flutter_skyle_configure_iokit_transport: NULL client");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    pthread_mutex_lock(&g_iokit_mutex);

    // While the transport supervisor runs with the ownership callback
    // registered, the PLATFORM CALLBACK owns the transport lifecycle
    // (skyle_link.h): a Dart-driven reconfigure (legacy auto-reconnect paths
    // call configure on every disconnect edge) must NOT destroy/recreate the
    // IOKit device claim here - mid-handover that fights the new USB owner
    // for the device and holds g_iokit_mutex against the supervisor's
    // ownership callback. Refresh the IDs for the next cb(true) and return;
    // the Skyle VID/PID never change at runtime in practice.
    if (g_usb_ownership_registered && skyle_link_supervisor_is_enabled()) {
        ctx->iokit_vendor_id = vendor_id;
        ctx->iokit_product_id = product_id;
        pthread_mutex_unlock(&g_iokit_mutex);
        LOGD("flutter_skyle_configure_iokit_transport: supervisor owns the transport lifecycle, skipping reconfigure");
        return 0;
    }

    // Destroy existing IOKit transport if any (reconfigure replaces it)
    if (ctx->iokit_transport) {
        skyle_transport_iokit_destroy(ctx->iokit_transport);
        ctx->iokit_transport = NULL;
    }
    ctx->iokit_vendor_id = vendor_id;
    ctx->iokit_product_id = product_id;

    int result = iokit_register_transport_locked(ctx, client);

    // First configure: hand the transport lifecycle to the platform layer for
    // Skyle Link handovers (macOS only - iOS runs push mode without a
    // supervisor and never reaches this function).
    if (result == 0 && !g_usb_ownership_registered) {
        skyle_link_set_usb_ownership_callback(iokit_usb_ownership_callback, NULL);
        g_usb_ownership_registered = true;
        LOGD("flutter_skyle_configure_iokit_transport: USB ownership callback registered");
    }

    pthread_mutex_unlock(&g_iokit_mutex);

    if (result != 0) {
        return result;
    }

    LOGD("flutter_skyle_configure_iokit_transport: IOKit transport configured (VID=0x%04X, PID=0x%04X)", vendor_id, product_id);
    return 0;
}
#endif

FLUTTER_SKYLE_EXPORT void flutter_skyle_clear_callbacks(skyle_client* client) {
    if (!client) return;

    LOGD("flutter_skyle_clear_callbacks: Clearing callbacks for client %p", client);

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGD("flutter_skyle_clear_callbacks: No context found, nothing to clear");
        return;
    }

#if TARGET_OS_OSX
    // Module: zero ALL subscriber slots under the mutex (atomic for any
    // adapter currently dispatching), then unregister the C adapters from
    // skyle_client so eap_process_message does not even reach them. A later
    // set/add call re-registers the adapters.
    flutter_skyle_fanout_clear(client);
#else
    // Zero the Dart callback pointers under the mutex first so any adapter
    // currently dispatching observes the change atomically.
    pthread_mutex_lock(&ctx->callback_mutex);
    memset(&ctx->dart_callbacks, 0, sizeof(flutter_skyle_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    // Also unregister our C adapters from skyle_client so eap_process_message
    // does not even reach them. Belt-and-suspenders against the case where
    // the Dart NativeCallable has been closed without our destroy() running -
    // e.g. engine teardown racing with an in-flight EA RunLoop event. A later
    // flutter_skyle_set_callbacks call (hot restart / second create()) will
    // re-register these adapters, so this is safe to do unconditionally.
    skyle_callback_config empty_config = {0};
    skyle_client_set_callbacks(client, &empty_config);
#endif

    LOGD("flutter_skyle_clear_callbacks: Callbacks cleared successfully");
}

FLUTTER_SKYLE_EXPORT void flutter_skyle_destroy(skyle_client* client) {
    if (!client) return;

    LOGD("flutter_skyle_destroy: Starting destruction for client %p", client);

    // Clear Dart callbacks first to prevent any stray invocations
    flutter_skyle_clear_callbacks(client);

    bridge_context* ctx = get_context_for_client(client);

    // Also clear the C-level adapter callbacks before destroying
    // (safe since we're about to stop all threads anyway)
    skyle_callback_config empty_config = {0};
    skyle_client_set_callbacks(client, &empty_config);

    // Unregister BEFORE destroying the client so that any in-flight
    // flutter_skyle_process_data call (iOS EA RunLoop fires on the same main
    // thread after this returns) sees g_client == NULL and returns early,
    // preventing a use-after-free into the freed bridge context.
    unregister_client_context(client);

    // Destroy client (this stops background thread and waits for it; it also
    // joins the Skyle Link supervisor first, so the USB ownership callback
    // cannot fire past this point)
    skyle_client_destroy(client);

#if TARGET_OS_OSX
    // Drop the ownership registration so a future create/configure cycle
    // starts clean (the supervisor is already stopped and joined above).
    pthread_mutex_lock(&g_iokit_mutex);
    if (g_usb_ownership_registered) {
        skyle_link_set_usb_ownership_callback(NULL, NULL);
        g_usb_ownership_registered = false;
    }
    if (ctx && ctx->iokit_transport) {
        skyle_transport_iokit_destroy(ctx->iokit_transport);
        ctx->iokit_transport = NULL;
    }
    pthread_mutex_unlock(&g_iokit_mutex);
#endif

    if (ctx) {
#if TARGET_OS_IOS
        free(ctx->calib_left_copy);
        free(ctx->calib_right_copy);
        pthread_mutex_destroy(&ctx->callback_mutex);
#endif
        free(ctx);
    }

    LOGD("flutter_skyle_destroy: Client destroyed");
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_connect(skyle_client* client) {
    if (!client) return -1;

    skyle_connection_state current_state = skyle_client_get_state(client);
    LOGD("flutter_skyle_connect: Current state: %d", (int)current_state);

    // While the transport supervisor runs, a Dart-initiated connect must never
    // force-reset the link: it would kill a healthy local (socket) link or a
    // supervisor-managed USB session with no closed notification. The
    // skyle_client_connect below is a supervisor kick in that case.
    if (current_state != SKYLE_STATE_DISCONNECTED && !skyle_link_supervisor_is_enabled()) {
        LOGD("flutter_skyle_connect: Client not in DISCONNECTED state (%d), resetting...", (int)current_state);
        skyle_client_disconnect(client);
    }

    skyle_result result = skyle_client_connect(client);
    if (result != SKYLE_OK) {
        LOGE("flutter_skyle_connect: Connect failed (%d)", result);
        return result;
    }

    LOGD("flutter_skyle_connect: Connected - background thread handles all I/O automatically");
    return 0;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_disconnect(skyle_client* client) {
    if (!client) return -1;

    // Only stop background thread if running (not in push mode where no threads are started)
    if (skyle_client_is_background_running(client)) {
        skyle_result bg_result = skyle_client_stop_background(client);
        if (bg_result != SKYLE_OK) {
            LOGD("flutter_skyle_disconnect: Background thread stop result: %d", bg_result);
        }
    }

    skyle_result result = skyle_client_disconnect(client);
    LOGD("flutter_skyle_disconnect: Disconnected");
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_gaze(skyle_client* client, bool enable) {
    if (!client) return -1;
    skyle_result result = skyle_client_enable_gaze(client, enable);
    LOGD("flutter_skyle_enable_gaze: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_positioning(skyle_client* client, bool enable) {
    if (!client) return -1;
    skyle_result result = skyle_client_enable_positioning(client, enable);
    LOGD("flutter_skyle_enable_positioning: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_request_version(skyle_client* client) {
    if (!client) return -1;
    skyle_result result = skyle_client_request_version(client);
    LOGD("flutter_skyle_request_version: Requested (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_control(skyle_client* client, bool enable) {
    if (!client) return -1;
    skyle_result result = skyle_client_enable_control(client, enable);
    LOGD("flutter_skyle_enable_control: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_send_control(skyle_client* client, const skyle_control_message* message) {
    if (!client) return -1;
    skyle_result result = skyle_client_send_control(client, message);
    LOGD("flutter_skyle_send_control: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_send_display_info(skyle_client* client, const skyle_set_display_info* info) {
    if (!client || !info) return -1;
    skyle_result result = skyle_client_send_display_info(client, info);
    LOGD("flutter_skyle_send_display_info: %ux%upx %.1fx%.1fmm (%d)",
         info->resolution.width, info->resolution.height,
         info->size_mm.width, info->size_mm.height, result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_start_calibration(skyle_client* client, const skyle_calibration_config* config) {
    if (!client) return -1;
    skyle_result result = skyle_client_start_calibration(client, config);
    LOGD("flutter_skyle_start_calibration: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_collect_calibration_points(skyle_client* client) {
    if (!client) return -1;
    skyle_result result = skyle_client_collect_calibration_points(client);
    LOGD("flutter_skyle_collect_calibration_points: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_abort_calibration(skyle_client* client) {
    if (!client) return -1;
    skyle_result result = skyle_client_abort_calibration(client);
    LOGD("flutter_skyle_abort_calibration: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_video(skyle_client* client, bool enable) {
    if (!client) return -1;
    skyle_result result = skyle_client_enable_video(client, enable);
    LOGD("flutter_skyle_enable_video: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_enable_logging(skyle_client* client, bool enable) {
    if (!client) return -1;
    skyle_result result = skyle_client_enable_logging(client, enable);
    LOGD("flutter_skyle_enable_logging: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_get_state(skyle_client* client) {
    if (!client) return -1;
    return (int)skyle_client_get_state(client);
}

FLUTTER_SKYLE_EXPORT const char* flutter_skyle_get_last_error(skyle_client* client) {
    if (!client) return NULL;
    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) return NULL;
#if TARGET_OS_OSX
    // The error buffer lives in the fan-out module (its on_error adapter
    // records the message before dispatching to the subscribers).
    return flutter_skyle_fanout_last_error();
#else
    return ctx->last_error[0] != '\0' ? ctx->last_error : NULL;
#endif
}

// =============================================================================
// File Transfer Functions
// =============================================================================

FLUTTER_SKYLE_EXPORT int flutter_skyle_upload_file(skyle_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash) {
    if (!client || !path || !data) return -1;
    skyle_result result = skyle_client_upload_file(client, path, data, data_len, sha256_hash);
    LOGD("flutter_skyle_upload_file: path=%s, size=%u (%d)", path, data_len, result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_cancel_upload(skyle_client* client) {
    if (!client) return -1;
    skyle_result result = skyle_client_cancel_upload(client);
    LOGD("flutter_skyle_cancel_upload: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT void flutter_skyle_free(void* ptr) {
    free(ptr);
}

// =============================================================================
// iOS Push-Based Transport Functions
// =============================================================================

#if TARGET_OS_IOS

FLUTTER_SKYLE_EXPORT int flutter_skyle_configure_push_transport(skyle_client* client,
    skyle_transport_write_fn write_fn,
    skyle_usb_device_check_fn device_check_fn,
    void* user_data) {
    if (!client || !write_fn) return -1;
    skyle_result result = skyle_client_set_push_transport(client, write_fn, device_check_fn, user_data);
    LOGD("flutter_skyle_configure_push_transport: (%d)", result);
    return result;
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_process_data(skyle_client* client,
    const uint8_t* data, uint16_t length) {
    if (!client || !data || length == 0) return -1;
    // Guard against calls arriving after destroy() unregistered the client.
    // On iOS the EA RunLoop and Dart both run on the main thread so there is
    // no concurrency concern; this check is enough to prevent UAF into a
    // freed bridge context when the EA stream outlives the Dart client.
    if (g_client == NULL || g_client != client) return -1;
    return skyle_client_process_received_data(client, data, length);
}

FLUTTER_SKYLE_EXPORT int flutter_skyle_tick(skyle_client* client) {
    if (!client) return -1;
    return skyle_client_tick(client);
}

#endif // TARGET_OS_IOS
