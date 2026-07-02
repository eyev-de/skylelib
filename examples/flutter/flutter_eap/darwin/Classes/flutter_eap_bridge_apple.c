/**
 * @file flutter_eap_bridge_apple.c
 * @brief FFI bridge implementation for Apple platforms (iOS/macOS)
 *
 * Architecture:
 *
 * iOS: Swift provides transport via ExternalAccessory (EASession)
 *   - Swift calls flutter_eap_set_apple_transport() with C function pointers
 *   - C background thread calls transport_read/write via those function pointers
 *
 * macOS: IOKit provides transport via USB bulk endpoints
 *   - Swift calls flutter_eap_configure_iokit_transport() for convenience
 *   - IOKit transport handles read/write/device_check entirely in C
 *
 * Dart Layer (both platforms):
 *   - Dart calls flutter_eap_set_callbacks() to register message handlers
 *   - C library parses protocol and invokes adapter callbacks
 *   - Adapters pass C structs by value to Dart
 */

#include "flutter_eap_bridge_apple.h"
#include <eap_client.h>
#include <eap/eap_message_types.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <TargetConditionals.h>

#if TARGET_OS_OSX
#include <eap_transport_iokit.h>
#endif

#define LOG_TAG "FlutterEapBridge"
#define LOGD(...) do { fprintf(stderr, "[" LOG_TAG "] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#define LOGE(...) do { fprintf(stderr, "[" LOG_TAG " ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)

// =============================================================================
// Internal structures and global state
// =============================================================================

typedef struct {
    flutter_eap_callbacks dart_callbacks;
    pthread_mutex_t callback_mutex;  // Protects dart_callbacks against dispatch thread race
    eap_client* client;
    char last_error[256];
    // Deep copies of calibration result arrays kept alive for async Dart callback
    eap_quality_point* calib_left_copy;
    eap_quality_point* calib_right_copy;
#if TARGET_OS_OSX
    eap_transport_iokit* iokit_transport;
#endif
} bridge_context;

static eap_client* g_client = NULL;
static bridge_context* g_context = NULL;

static bridge_context* get_context_for_client(eap_client* client) {
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

// =============================================================================
// C-to-Dart callback adapters (identical to Android bridge)
// =============================================================================

static void on_gaze_adapter(eap_client* client, const eap_gaze_response* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_gaze) {
        ctx->dart_callbacks.on_gaze(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_positioning_adapter(eap_client* client, const eap_positioning_response* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_positioning) {
        ctx->dart_callbacks.on_positioning(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_version_adapter(eap_client* client, const eap_version_response* version, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !version) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_version) {
        ctx->dart_callbacks.on_version(*version, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_control_adapter(eap_client* client, const eap_control_message* data, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !data) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_control) {
        ctx->dart_callbacks.on_control(*data, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_point_adapter(eap_client* client, const eap_next_calibration_point* point, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !point) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_point) {
        ctx->dart_callbacks.on_calibration_point(*point, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_progress_adapter(eap_client* client, const eap_collecting_calibration_points* progress, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !progress) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_progress) {
        ctx->dart_callbacks.on_calibration_progress(*progress, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_paused_adapter(eap_client* client, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_calibration_paused) {
        ctx->dart_callbacks.on_calibration_paused(ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_calibration_finished_adapter(eap_client* client, const eap_finished_calibration* result, void* user_data) {
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

        eap_finished_calibration copy = *result;

        if (result->left_count > 0 && result->left) {
            size_t left_size = result->left_count * sizeof(eap_quality_point);
            ctx->calib_left_copy = (eap_quality_point*)malloc(left_size);
            if (ctx->calib_left_copy) {
                memcpy(ctx->calib_left_copy, result->left, left_size);
                copy.left = ctx->calib_left_copy;
            }
        }

        if (result->right_count > 0 && result->right) {
            size_t right_size = result->right_count * sizeof(eap_quality_point);
            ctx->calib_right_copy = (eap_quality_point*)malloc(right_size);
            if (ctx->calib_right_copy) {
                memcpy(ctx->calib_right_copy, result->right, right_size);
                copy.right = ctx->calib_right_copy;
            }
        }

        ctx->dart_callbacks.on_calibration_finished(copy, ctx->dart_callbacks.user_data);
    }
    pthread_mutex_unlock(&ctx->callback_mutex);
}

static void on_state_change_adapter(eap_client* client, eap_connection_state old_state,
                                    eap_connection_state new_state, void* user_data) {
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

static void on_error_adapter(eap_client* client, eap_result error, const char* message, void* user_data) {
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

static void on_video_adapter(eap_client* client, const eap_video_response* video,
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

static void on_file_status_adapter(eap_client* client,
    const eap_file_status_response* status, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !status) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_file_status) {
        // NativeCallable.listener posts to a Dart port — the callback runs
        // asynchronously. The error_message pointer must survive until Dart
        // reads it, so heap-allocate a copy. Dart frees it after reading.
        char* error_msg = NULL;
        if (status->status == EAP_FILE_STATUS_FAILED && status->error_message[0] != '\0') {
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

static void on_logging_adapter(eap_client* client,
    const eap_logging_response* log, void* user_data) {
    (void)client;
    bridge_context* ctx = (bridge_context*)user_data;
    if (!ctx || !log) return;

    pthread_mutex_lock(&ctx->callback_mutex);
    if (ctx->dart_callbacks.on_logging) {
        // strdup so the message survives the async hop to Dart via
        // NativeCallable.listener; Dart frees with flutter_eap_free.
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

// =============================================================================
// Public API Implementation
// =============================================================================

static bridge_context* ensure_context(eap_client* client) {
    bridge_context* ctx = get_context_for_client(client);
    if (ctx) return ctx;

    ctx = (bridge_context*)calloc(1, sizeof(bridge_context));
    if (!ctx) {
        LOGE("ensure_context: Failed to allocate context");
        return NULL;
    }
    pthread_mutex_init(&ctx->callback_mutex, NULL);
    ctx->client = client;
    ctx->calib_left_copy = NULL;
    ctx->calib_right_copy = NULL;
#if TARGET_OS_OSX
    ctx->iokit_transport = NULL;
#endif
    register_client_context(client, ctx);
    return ctx;
}

EAP_EXPORT eap_client* flutter_eap_create_with_transport(void) {
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

EAP_EXPORT bool flutter_eap_is_initialized(void) {
    return g_context != NULL;
}

EAP_EXPORT eap_client* flutter_eap_get_instance(void) {
    return eap_client_get_instance();
}

EAP_EXPORT int flutter_eap_set_callbacks(eap_client* client, const flutter_eap_callbacks* callbacks) {
    if (!client || !callbacks) {
        LOGE("flutter_eap_set_callbacks: NULL parameters");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    // Mutex-protected for hot restart safety
    pthread_mutex_lock(&ctx->callback_mutex);
    memcpy(&ctx->dart_callbacks, callbacks, sizeof(flutter_eap_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    eap_callback_config callback_config = {
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

    eap_result result = eap_client_set_callbacks(client, &callback_config);
    if (result != EAP_OK) {
        LOGE("flutter_eap_set_callbacks: eap_client_set_callbacks failed (%d)", result);
        return (int)result;
    }

    LOGD("flutter_eap_set_callbacks: Callbacks registered successfully for client %p", client);
    return 0;
}

EAP_EXPORT void flutter_eap_set_apple_transport(
    eap_client* client,
    eap_transport_read_fn read_fn,
    eap_transport_write_fn write_fn,
    eap_usb_device_check_fn device_check_fn,
    void* user_data
) {
    if (!client) {
        LOGE("flutter_eap_set_apple_transport: NULL client");
        return;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return;

    eap_transport_config transport_config = {
        .transport_write = write_fn,
        .transport_read = read_fn,
        .usb_device_check = device_check_fn,
        .transport_user_data = user_data,
        .connect_timeout_ms = 10000,
        .reconnect_interval_ms = 1000,
        .verbose = false
    };

    eap_result result = eap_client_set_transport(client, &transport_config);
    if (result != EAP_OK) {
        LOGE("flutter_eap_set_apple_transport: eap_client_set_transport failed (%d)", result);
        return;
    }

    LOGD("flutter_eap_set_apple_transport: Transport configured successfully");
}

#if TARGET_OS_OSX
EAP_EXPORT int flutter_eap_configure_iokit_transport(eap_client* client, uint16_t vendor_id, uint16_t product_id) {
    if (!client) {
        LOGE("flutter_eap_configure_iokit_transport: NULL client");
        return -1;
    }

    bridge_context* ctx = ensure_context(client);
    if (!ctx) return -1;

    // Destroy existing IOKit transport if any
    if (ctx->iokit_transport) {
        eap_transport_iokit_destroy(ctx->iokit_transport);
        ctx->iokit_transport = NULL;
    }

    eap_transport_iokit_config iokit_config = {
        .vendor_id = vendor_id,
        .product_id = product_id,
        .timeout_ms = 1000,
        .verbose = false
    };

    ctx->iokit_transport = eap_transport_iokit_create(&iokit_config);
    if (!ctx->iokit_transport) {
        LOGD("flutter_eap_configure_iokit_transport: Device not present yet, transport will connect when available");
    }

    // Set transport using IOKit functions
    eap_transport_config transport_config = {
        .transport_write = eap_transport_iokit_write,
        .transport_read = eap_transport_iokit_read,
        .usb_device_check = eap_transport_iokit_get_check_callback(),
        .transport_user_data = ctx->iokit_transport,
        .connect_timeout_ms = 10000,
        .reconnect_interval_ms = 1000,
        .verbose = false
    };

    eap_result result = eap_client_set_transport(client, &transport_config);
    if (result != EAP_OK) {
        LOGE("flutter_eap_configure_iokit_transport: eap_client_set_transport failed (%d)", result);
        return (int)result;
    }

    LOGD("flutter_eap_configure_iokit_transport: IOKit transport configured (VID=0x%04X, PID=0x%04X)", vendor_id, product_id);
    return 0;
}
#endif

EAP_EXPORT void flutter_eap_clear_callbacks(eap_client* client) {
    if (!client) return;

    LOGD("flutter_eap_clear_callbacks: Clearing callbacks for client %p", client);

    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) {
        LOGD("flutter_eap_clear_callbacks: No context found, nothing to clear");
        return;
    }

    // Zero the Dart callback pointers under the mutex first so any adapter
    // currently dispatching observes the change atomically.
    pthread_mutex_lock(&ctx->callback_mutex);
    memset(&ctx->dart_callbacks, 0, sizeof(flutter_eap_callbacks));
    pthread_mutex_unlock(&ctx->callback_mutex);

    // Also unregister our C adapters from eap_client so eap_process_message
    // does not even reach them. Belt-and-suspenders against the case where
    // the Dart NativeCallable has been closed without our destroy() running -
    // e.g. engine teardown racing with an in-flight EA RunLoop event. A later
    // flutter_eap_set_callbacks call (hot restart / second create()) will
    // re-register these adapters, so this is safe to do unconditionally.
    eap_callback_config empty_config = {0};
    eap_client_set_callbacks(client, &empty_config);

    LOGD("flutter_eap_clear_callbacks: Callbacks cleared successfully");
}

EAP_EXPORT void flutter_eap_destroy(eap_client* client) {
    if (!client) return;

    LOGD("flutter_eap_destroy: Starting destruction for client %p", client);

    // Clear Dart callbacks first to prevent any stray invocations
    flutter_eap_clear_callbacks(client);

    bridge_context* ctx = get_context_for_client(client);

    // Also clear the C-level adapter callbacks before destroying
    // (safe since we're about to stop all threads anyway)
    eap_callback_config empty_config = {0};
    eap_client_set_callbacks(client, &empty_config);

    // Unregister BEFORE destroying the client so that any in-flight
    // flutter_eap_process_data call (iOS EA RunLoop fires on the same main
    // thread after this returns) sees g_client == NULL and returns early,
    // preventing a use-after-free into the freed bridge context.
    unregister_client_context(client);

    // Destroy client (this stops background thread and waits for it)
    eap_client_destroy(client);

    if (ctx) {
        free(ctx->calib_left_copy);
        free(ctx->calib_right_copy);
#if TARGET_OS_OSX
        if (ctx->iokit_transport) {
            eap_transport_iokit_destroy(ctx->iokit_transport);
            ctx->iokit_transport = NULL;
        }
#endif
        pthread_mutex_destroy(&ctx->callback_mutex);
        free(ctx);
    }

    LOGD("flutter_eap_destroy: Client destroyed");
}

EAP_EXPORT int flutter_eap_connect(eap_client* client) {
    if (!client) return -1;

    eap_connection_state current_state = eap_client_get_state(client);
    LOGD("flutter_eap_connect: Current state: %d", (int)current_state);

    if (current_state != EAP_STATE_DISCONNECTED) {
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

EAP_EXPORT int flutter_eap_disconnect(eap_client* client) {
    if (!client) return -1;

    // Only stop background thread if running (not in push mode where no threads are started)
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

EAP_EXPORT int flutter_eap_enable_gaze(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_gaze(client, enable);
    LOGD("flutter_eap_enable_gaze: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

EAP_EXPORT int flutter_eap_enable_positioning(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_positioning(client, enable);
    LOGD("flutter_eap_enable_positioning: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

EAP_EXPORT int flutter_eap_request_version(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_request_version(client);
    LOGD("flutter_eap_request_version: Requested (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_enable_control(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_control(client, enable);
    LOGD("flutter_eap_enable_control: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

EAP_EXPORT int flutter_eap_send_control(eap_client* client, const eap_control_message* message) {
    if (!client) return -1;
    eap_result result = eap_client_send_control(client, message);
    LOGD("flutter_eap_send_control: (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_send_display_info(eap_client* client, const eap_set_display_info* info) {
    if (!client || !info) return -1;
    eap_result result = eap_client_send_display_info(client, info);
    LOGD("flutter_eap_send_display_info: %ux%upx %.1fx%.1fmm (%d)",
         info->resolution.width, info->resolution.height,
         info->size_mm.width, info->size_mm.height, result);
    return result;
}

EAP_EXPORT int flutter_eap_start_calibration(eap_client* client, const eap_calibration_config* config) {
    if (!client) return -1;
    eap_result result = eap_client_start_calibration(client, config);
    LOGD("flutter_eap_start_calibration: (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_collect_calibration_points(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_collect_calibration_points(client);
    LOGD("flutter_eap_collect_calibration_points: (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_abort_calibration(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_abort_calibration(client);
    LOGD("flutter_eap_abort_calibration: (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_enable_video(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_video(client, enable);
    LOGD("flutter_eap_enable_video: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

EAP_EXPORT int flutter_eap_enable_logging(eap_client* client, bool enable) {
    if (!client) return -1;
    eap_result result = eap_client_enable_logging(client, enable);
    LOGD("flutter_eap_enable_logging: %s (%d)", enable ? "enabled" : "disabled", result);
    return result;
}

EAP_EXPORT int flutter_eap_get_state(eap_client* client) {
    if (!client) return -1;
    return (int)eap_client_get_state(client);
}

EAP_EXPORT const char* flutter_eap_get_last_error(eap_client* client) {
    if (!client) return NULL;
    bridge_context* ctx = get_context_for_client(client);
    if (!ctx) return NULL;
    return ctx->last_error[0] != '\0' ? ctx->last_error : NULL;
}

// =============================================================================
// File Transfer Functions
// =============================================================================

EAP_EXPORT int flutter_eap_upload_file(eap_client* client, const char* path,
    uint8_t* data, uint32_t data_len, const uint8_t* sha256_hash) {
    if (!client || !path || !data) return -1;
    eap_result result = eap_client_upload_file(client, path, data, data_len, sha256_hash);
    LOGD("flutter_eap_upload_file: path=%s, size=%u (%d)", path, data_len, result);
    return result;
}

EAP_EXPORT int flutter_eap_cancel_upload(eap_client* client) {
    if (!client) return -1;
    eap_result result = eap_client_cancel_upload(client);
    LOGD("flutter_eap_cancel_upload: (%d)", result);
    return result;
}

EAP_EXPORT void flutter_eap_free(void* ptr) {
    free(ptr);
}

// =============================================================================
// iOS Push-Based Transport Functions
// =============================================================================

#if TARGET_OS_IOS

EAP_EXPORT int flutter_eap_configure_push_transport(eap_client* client,
    eap_transport_write_fn write_fn,
    eap_usb_device_check_fn device_check_fn,
    void* user_data) {
    if (!client || !write_fn) return -1;
    eap_result result = eap_client_set_push_transport(client, write_fn, device_check_fn, user_data);
    LOGD("flutter_eap_configure_push_transport: (%d)", result);
    return result;
}

EAP_EXPORT int flutter_eap_process_data(eap_client* client,
    const uint8_t* data, uint16_t length) {
    if (!client || !data || length == 0) return -1;
    // Guard against calls arriving after destroy() unregistered the client.
    // On iOS the EA RunLoop and Dart both run on the main thread so there is
    // no concurrency concern; this check is enough to prevent UAF into a
    // freed bridge context when the EA stream outlives the Dart client.
    if (g_client == NULL || g_client != client) return -1;
    return eap_client_process_received_data(client, data, length);
}

EAP_EXPORT int flutter_eap_tick(eap_client* client) {
    if (!client) return -1;
    return eap_client_tick(client);
}

#endif // TARGET_OS_IOS
