/**
 * @file flutter_skyle_fanout.c
 * @brief Shared multi-engine callback fan-out implementation.
 *
 * Pure semantic lift of the Android bridge's subscriber machinery (see
 * flutter_skyle_fanout.h). Everything here is platform-neutral C17; the only
 * platform splits are logging, the module mutex, and strdup.
 */

#include "flutter_skyle_fanout.h"

#include <skylelib/messages/skyle_message_types.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// =============================================================================
// Platform shims: logging, mutex, strdup
// =============================================================================

// The Apple build pulls this file into skylelib_unity.c AFTER the platform
// bridge, which defines the same logging macros - redefine cleanly. The tag
// stays "FlutterSkyleBridge": this IS the lifted bridge machinery, and the
// Android logcat output must not change.
#undef LOG_TAG
#undef LOGD
#undef LOGE
#define LOG_TAG "FlutterSkyleBridge"

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
static SRWLOCK g_fanout_lock = SRWLOCK_INIT;
#define FANOUT_LOCK() AcquireSRWLockExclusive(&g_fanout_lock)
#define FANOUT_UNLOCK() ReleaseSRWLockExclusive(&g_fanout_lock)
static char* fanout_strdup(const char* s) { return _strdup(s); }
#else
#include <pthread.h>
static pthread_mutex_t g_fanout_lock = PTHREAD_MUTEX_INITIALIZER;
#define FANOUT_LOCK() pthread_mutex_lock(&g_fanout_lock)
#define FANOUT_UNLOCK() pthread_mutex_unlock(&g_fanout_lock)
static char* fanout_strdup(const char* s) { return strdup(s); }
#endif

// =============================================================================
// Subscriber table (protected by g_fanout_lock against the dispatch thread)
// =============================================================================

/**
 * One registered Dart callback subscriber (one per Flutter engine).
 * handle == 0 marks a free slot. Calibration result arrays are deep-copied
 * per subscriber because NativeCallable.listener delivers asynchronously;
 * each slot's copies stay alive until the next dispatch or removal.
 */
typedef struct {
    int64_t handle;
    int64_t engine_token;  // 0 = none; non-zero enables same-token reaping
    flutter_skyle_callbacks cbs;
    skyle_quality_point* calib_left_copy;
    skyle_quality_point* calib_right_copy;
} eap_subscriber;

static eap_subscriber g_subscribers[FLUTTER_SKYLE_MAX_SUBSCRIBERS];
static int64_t g_next_subscriber_handle = 1;  // Monotonic; 0 is "free slot"

// Last error captured by the on_error adapter (racy plain reads/writes, same
// as the pre-lift per-context buffer - readers only ever see a full previous
// message or a truncated newer one).
static char g_last_error[256];

/** Free one subscriber slot's calibration copies and mark it free. Caller holds g_fanout_lock. */
static void free_subscriber_slot(eap_subscriber* sub) {
    free(sub->calib_left_copy);
    free(sub->calib_right_copy);
    memset(sub, 0, sizeof(eap_subscriber));
}

// =============================================================================
// C-to-Dart callback adapters
// =============================================================================
//
// Installed on the core skyle_client via install_core_adapters(); called by the
// C library's dispatch/I-O threads when messages are parsed. Each adapter
// fans the event out to every subscriber that registered the matching
// function pointer, applying the per-subscriber payload-copy rules documented
// in the header.
//

/**
 * Gaze callback adapter - passes skyle_gaze_response struct directly to Dart
 */
static void on_gaze_adapter(skyle_client* client, const skyle_gaze_response* data, void* user_data) {
    (void)client;
    (void)user_data;
    if (!data) return;

    // Mutex protects against subscriber add/remove racing the dispatch thread
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_gaze) {
            sub->cbs.on_gaze(*data, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Positioning callback adapter - passes skyle_positioning_response struct directly to Dart
 */
static void on_positioning_adapter(skyle_client* client, const skyle_positioning_response* data, void* user_data) {
    (void)client;
    (void)user_data;
    if (!data) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_positioning) {
            sub->cbs.on_positioning(*data, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Version callback adapter - passes skyle_version_response struct directly to Dart
 */
static void on_version_adapter(skyle_client* client, const skyle_version_response* version, void* user_data) {
    (void)client;
    (void)user_data;
    if (!version) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_version) {
            sub->cbs.on_version(*version, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Control callback adapter - passes skyle_control_message struct directly to Dart
 */
static void on_control_adapter(skyle_client* client, const skyle_control_message* data, void* user_data) {
    (void)client;
    (void)user_data;
    if (!data) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_control) {
            sub->cbs.on_control(*data, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Calibration point callback adapter - passes skyle_next_calibration_point struct directly to Dart
 */
static void on_calibration_point_adapter(skyle_client* client, const skyle_next_calibration_point* point, void* user_data) {
    (void)client;
    (void)user_data;
    if (!point) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_calibration_point) {
            sub->cbs.on_calibration_point(*point, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Calibration progress callback adapter - passes skyle_collecting_calibration_points struct directly to Dart
 */
static void on_calibration_progress_adapter(skyle_client* client, const skyle_collecting_calibration_points* progress, void* user_data) {
    (void)client;
    (void)user_data;
    if (!progress) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_calibration_progress) {
            sub->cbs.on_calibration_progress(*progress, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Calibration paused callback adapter
 */
static void on_calibration_paused_adapter(skyle_client* client, void* user_data) {
    (void)client;
    (void)user_data;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_calibration_paused) {
            sub->cbs.on_calibration_paused(sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Calibration finished callback adapter - passes skyle_finished_calibration struct directly to Dart
 */
static void on_calibration_finished_adapter(skyle_client* client, const skyle_finished_calibration* result, void* user_data) {
    (void)client;
    (void)user_data;
    if (!result) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_calibration_finished) continue;

        // Deep copy quality point arrays PER SUBSCRIBER - NativeCallable.listener
        // is async, so the original arrays will be freed before Dart processes
        // the callback. Each slot keeps its copies alive until the next dispatch
        // or the subscriber's removal.
        free(sub->calib_left_copy);
        free(sub->calib_right_copy);
        sub->calib_left_copy = NULL;
        sub->calib_right_copy = NULL;

        skyle_finished_calibration copy = *result;

        if (result->left_count > 0 && result->left) {
            size_t left_size = result->left_count * sizeof(skyle_quality_point);
            sub->calib_left_copy = (skyle_quality_point*)malloc(left_size);
            if (sub->calib_left_copy) {
                memcpy(sub->calib_left_copy, result->left, left_size);
                copy.left = sub->calib_left_copy;
            }
        }

        if (result->right_count > 0 && result->right) {
            size_t right_size = result->right_count * sizeof(skyle_quality_point);
            sub->calib_right_copy = (skyle_quality_point*)malloc(right_size);
            if (sub->calib_right_copy) {
                memcpy(sub->calib_right_copy, result->right, right_size);
                copy.right = sub->calib_right_copy;
            }
        }

        sub->cbs.on_calibration_finished(copy, sub->cbs.user_data);
    }
    FANOUT_UNLOCK();
}

/**
 * State change callback adapter
 */
static void on_state_change_adapter(skyle_client* client, skyle_connection_state old_state,
                                    skyle_connection_state new_state, void* user_data) {
    (void)client;
    (void)old_state;  // Unused - Dart only needs new state
    (void)user_data;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_state_change) {
            sub->cbs.on_state_change((int)new_state, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Error callback adapter
 */
static void on_error_adapter(skyle_client* client, skyle_result error, const char* message, void* user_data) {
    (void)client;
    (void)user_data;
    if (!message) return;

    // Log error for debugging
    LOGE("on_error_adapter: Error code=%d, message='%s'", (int)error, message);

    // Store error message
    strncpy(g_last_error, message, sizeof(g_last_error) - 1);
    g_last_error[sizeof(g_last_error) - 1] = '\0';

    // Invoke Dart callbacks
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle != 0 && sub->cbs.on_error) {
            sub->cbs.on_error(message, sub->cbs.user_data);
        }
    }
    FANOUT_UNLOCK();
}

/**
 * Video frame callback adapter
 * Called directly from I/O thread when a chunked transfer completes.
 * Data pointer is only valid during this callback.
 * Converts to RGBA in C (compiler auto-vectorises) so Dart receives
 * ready-to-display pixels with no per-pixel loop on the UI thread.
 */
static void on_video_adapter(skyle_client* client, const skyle_video_response* video,
                              void* user_data) {
    (void)client;
    (void)user_data;
    if (!video || !video->pixel_data) return;

    FANOUT_LOCK();

    // Count subscribers first: the RGBA conversion is only done when someone
    // is listening, and the LAST matching subscriber takes ownership of the
    // original buffer (earlier ones get copies, made BEFORE the original is
    // handed to Dart - each Dart isolate frees its own buffer asynchronously
    // via flutter_skyle_free, so copying from an already-delivered buffer would
    // race that free).
    int matching = 0;
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].handle != 0 && g_subscribers[i].cbs.on_video) matching++;
    }
    if (matching == 0) {
        FANOUT_UNLOCK();
        return;
    }

    // Use uint64_t to detect overflow before casting: pixel_count * 4 can
    // silently overflow uint32_t when width/height contain garbage values
    // from a corrupted or partially-assembled frame (e.g. during shutdown).
    // 64 MB is a generous upper bound (640x480 RGBA = ~1.2 MB).
    const uint32_t pixel_count = (uint32_t)video->width * (uint32_t)video->height;
    const uint64_t rgba_size_64 = (uint64_t)pixel_count * 4;
    if (pixel_count == 0 || rgba_size_64 > (64u * 1024u * 1024u)) {
        FANOUT_UNLOCK();
        return;
    }
    const uint32_t rgba_size = (uint32_t)rgba_size_64;
    uint8_t* rgba = (uint8_t*)malloc(rgba_size);
    if (!rgba) {
        FANOUT_UNLOCK();
        return;
    }

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

    bool original_delivered = false;
    int remaining = matching;
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_video) continue;
        remaining--;
        uint8_t* payload;
        if (remaining == 0) {
            payload = rgba;  // Last subscriber takes ownership of the original
            original_delivered = true;
        } else {
            payload = (uint8_t*)malloc(rgba_size);
            if (!payload) continue;
            memcpy(payload, rgba, rgba_size);
        }
        sub->cbs.on_video(payload, rgba_size, video->width, video->height, 4, sub->cbs.user_data);
    }
    if (!original_delivered) {
        free(rgba);
    }

    FANOUT_UNLOCK();
}

/**
 * File status callback adapter
 * Called when device sends StatusFile response during file transfer.
 */
static void on_file_status_adapter(skyle_client* client,
    const skyle_file_status_response* status, void* user_data) {
    (void)client;
    (void)user_data;
    if (!status) {
        LOGE("on_file_status_adapter: NULL status");
        return;
    }

    LOGD("on_file_status_adapter: status=%d progress=%d error='%s'",
         (int)status->status, (int)status->progress,
         (status->error_message[0] != '\0') ? status->error_message : "(none)");

    FANOUT_LOCK();
    int delivered = 0;
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_file_status) continue;
        // NativeCallable.listener posts to a Dart port - the callback runs
        // asynchronously. Heap-allocate the error string PER SUBSCRIBER so it
        // survives; each Dart side frees its own copy after reading.
        char* error_msg = NULL;
        if (status->status == SKYLE_FILE_STATUS_FAILED && status->error_message[0] != '\0') {
            error_msg = fanout_strdup(status->error_message);
        }
        sub->cbs.on_file_status(
            (uint16_t)status->status,
            status->progress,
            error_msg,
            sub->cbs.user_data
        );
        delivered++;
    }
    if (delivered == 0) {
        LOGE("on_file_status_adapter: no subscriber registered on_file_status - Dart will not receive this event!");
    }
    FANOUT_UNLOCK();
}

/**
 * Logging callback adapter - forwards device log lines to Dart.
 * The message is heap-allocated (strdup) so it survives the async hop to
 * Dart via NativeCallable.listener; Dart frees it with flutter_skyle_free.
 */
static void on_logging_adapter(skyle_client* client,
    const skyle_logging_response* log, void* user_data) {
    (void)client;
    (void)user_data;
    if (!log) return;

    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_logging) continue;
        // strdup per subscriber: each Dart isolate frees its own copy.
        char* msg = (log->message_len > 0) ? fanout_strdup(log->message) : NULL;
        sub->cbs.on_logging(
            (uint8_t)log->level,
            msg,
            log->header.timestamp_ms,
            sub->cbs.user_data
        );
    }
    FANOUT_UNLOCK();
}

// =============================================================================
// Adapter installation
// =============================================================================

/**
 * Install the C adapter set on the core client. Idempotent - safe to call on
 * every subscriber registration (skyle_client_set_callbacks overwrites with the
 * identical config).
 */
static int install_core_adapters(skyle_client* client) {
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
        .user_data = NULL  // Adapters use module state, no context needed
    };

    skyle_result result = skyle_client_set_callbacks(client, &callback_config);
    if (result != SKYLE_OK) {
        LOGE("install_core_adapters: skyle_client_set_callbacks failed (%d)", result);
        return (int)result;
    }
    return 0;
}

// =============================================================================
// Module API
// =============================================================================

int64_t flutter_skyle_fanout_add(skyle_client* client, const flutter_skyle_callbacks* callbacks, int64_t engine_token) {
    if (!client || !callbacks) {
        return -1;
    }

    int64_t handle = 0;
    FANOUT_LOCK();
    // Same-token re-add (desktop hot restart): reap the previous subscriber
    // carrying this engine's token before claiming a slot - its function
    // pointers belong to a dead isolate.
    if (engine_token != 0) {
        for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
            if (g_subscribers[i].handle != 0 && g_subscribers[i].engine_token == engine_token) {
                LOGD("flutter_skyle_fanout_add: reaped stale subscriber handle=%lld (engine_token=%lld)",
                     (long long)g_subscribers[i].handle, (long long)engine_token);
                free_subscriber_slot(&g_subscribers[i]);
            }
        }
    }
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].handle == 0) {
            g_subscribers[i].handle = g_next_subscriber_handle++;
            g_subscribers[i].engine_token = engine_token;
            g_subscribers[i].cbs = *callbacks;
            g_subscribers[i].calib_left_copy = NULL;
            g_subscribers[i].calib_right_copy = NULL;
            handle = g_subscribers[i].handle;
            break;
        }
    }
    FANOUT_UNLOCK();

    if (handle == 0) {
        return -2;
    }

    if (install_core_adapters(client) != 0) {
        flutter_skyle_fanout_remove(handle);
        return -1;
    }

    return handle;
}

int flutter_skyle_fanout_remove(int64_t handle) {
    if (handle <= 0) {
        return -1;
    }

    int result = -1;
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].handle == handle) {
            free_subscriber_slot(&g_subscribers[i]);
            result = 0;
            break;
        }
    }
    FANOUT_UNLOCK();

    // Deliberately do NOT unregister the core adapters even when the table is
    // now empty: other engines may subscribe at any time, and empty-table
    // adapters are cheap no-ops.
    return result;
}

int flutter_skyle_fanout_set_single(skyle_client* client, const flutter_skyle_callbacks* callbacks) {
    if (!client || !callbacks) {
        return -1;
    }

    // Legacy replace-all-with-one semantics: clear the whole subscriber table,
    // then register the caller as the only subscriber. Preserves the pre-fan-out
    // single-owner behavior for callers that never migrated to add_callbacks.
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].handle != 0) {
            free_subscriber_slot(&g_subscribers[i]);
        }
    }
    g_subscribers[0].handle = g_next_subscriber_handle++;
    g_subscribers[0].cbs = *callbacks;
    FANOUT_UNLOCK();

    return install_core_adapters(client);
}

void flutter_skyle_fanout_clear(skyle_client* client) {
    if (!client) {
        return;
    }

    // Zero ALL subscriber slots under the mutex first so any adapter currently
    // dispatching observes the change atomically.
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].handle != 0) {
            free_subscriber_slot(&g_subscribers[i]);
        }
    }
    FANOUT_UNLOCK();

    // Also unregister our C adapters from skyle_client so eap_process_message
    // does not even reach them. Belt-and-suspenders against the case where
    // a Dart NativeCallable has been closed without its destroy() running -
    // e.g. engine teardown racing with an in-flight read on the I/O thread.
    // A later flutter_skyle_set_callbacks/add_callbacks call will re-register
    // these adapters, so this is safe to do unconditionally.
    skyle_callback_config empty_config = {0};
    skyle_client_set_callbacks(client, &empty_config);
}

void flutter_skyle_fanout_dispatch_suspend_state(bool suspended, const char* holder) {
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_suspend_state) continue;
        char* holder_copy = holder ? fanout_strdup(holder) : NULL;
        sub->cbs.on_suspend_state(suspended, holder_copy, sub->cbs.user_data);
    }
    FANOUT_UNLOCK();
}

void flutter_skyle_fanout_dispatch_host_control(uint16_t control_id, const uint8_t* value, uint16_t value_len, const char* sender_app_id) {
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_host_control) continue;
        // Heap copies per subscriber: NativeCallable.listener delivers
        // asynchronously, each Dart isolate frees its own via flutter_skyle_free.
        uint8_t* value_copy = NULL;
        if (value && value_len > 0) {
            value_copy = (uint8_t*)malloc(value_len);
            if (value_copy) {
                memcpy(value_copy, value, value_len);
            }
        }
        char* sender_copy = sender_app_id ? fanout_strdup(sender_app_id) : NULL;
        sub->cbs.on_host_control(control_id, value_copy, value_copy ? (int32_t)value_len : 0, sender_copy, sub->cbs.user_data);
    }
    FANOUT_UNLOCK();
}

void flutter_skyle_fanout_dispatch_link_client(bool connected, const char* app_id, int client_count) {
    FANOUT_LOCK();
    for (int i = 0; i < FLUTTER_SKYLE_MAX_SUBSCRIBERS; i++) {
        eap_subscriber* sub = &g_subscribers[i];
        if (sub->handle == 0 || !sub->cbs.on_link_client) continue;
        char* app_id_copy = app_id ? fanout_strdup(app_id) : NULL;
        sub->cbs.on_link_client(connected, app_id_copy, client_count, sub->cbs.user_data);
    }
    FANOUT_UNLOCK();
}

const char* flutter_skyle_fanout_last_error(void) {
    return g_last_error[0] != '\0' ? g_last_error : NULL;
}
