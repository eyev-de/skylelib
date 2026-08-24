# skylelib — Public API Reference

**skylelib** is eyeV's cross-platform C17 library for communicating with the
**Skyle** eye-tracker (VID `0x3729`, PID `0x7333`) over USB. It speaks Apple's
iAP2 link protocol with the EAP session message layer on
top, and exposes a small, opaque C API with typed callbacks for gaze,
positioning, video, calibration and more.

This document describes the **public API** — everything shipped in the
`include/skylelib/` headers bundled with each
[release](https://github.com/eyev-de/skylelib/releases). All symbols are
annotated with `SKYLELIB_API` (the export macro) and declared `extern "C"`, so
the library is directly consumable from C, C++, and via FFI/P-Invoke bindings
(the [examples](README.md) use .NET, Swift and Dart).

- **Main header:** `#include <skylelib/skyle_client.h>` — pulls in every message
  type and structure you need.
- **Language:** C17, C ABI. Opaque `skyle_client` handle.
- **Byte order:** all wire data is **big-endian**. The library handles this for
  you; if you parse payloads yourself, use the `eap_read_*_be()` helpers in
  `eap/skyle_types.h` — never `memcpy` multi-byte values.

> Looking for a runnable starting point? See the
> [Avalonia / SwiftUI / Flutter examples](README.md).

---

## Table of contents

1. [Core concepts](#core-concepts)
2. [Quick start](#quick-start)
3. [Lifecycle](#lifecycle)
4. [Transport configuration](#transport-configuration)
5. [Callback configuration](#callback-configuration)
6. [Connection management](#connection-management)
7. [Streaming & message API](#streaming--message-api)
8. [Calibration](#calibration)
9. [File upload](#file-upload)
10. [Push-based API (iOS)](#push-based-api-ios)
11. [Data structures](#data-structures)
12. [Enumerations & return codes](#enumerations--return-codes)
13. [Utility helpers](#utility-helpers)
14. [Threading model](#threading-model)
15. [Versioning](#versioning)

---

## Core concepts

**Singleton client.** The library manages one client instance internally.
`skyle_client_get_instance()` returns it (creating it on first call). You do not
allocate it yourself.

**Two-phase configuration.** Configure the client in two independent steps, in
either order:

1. **Transport** (`skyle_client_set_transport`) — platform-specific USB read/write
   callbacks. Setting this starts the background I/O and send threads.
2. **Callbacks** (`skyle_client_set_callbacks`) — your application-level handlers
   for gaze, positioning, state changes, etc.

**Automatic handshake.** After `skyle_client_connect()`, the library runs the full
iAP2 + EAP handshake on its background thread and drives a 9-state connection
machine. You only send stream/control messages once the state reaches
`SKYLE_STATE_LINK_SYNCED`.

**Callbacks run on the I/O thread.** All message callbacks are invoked from the
library's background thread. Marshal to your UI/main thread before touching UI
state.

---

## Quick start

```c
#include <skylelib/skyle_client.h>

static void on_gaze(skyle_client* c, const skyle_gaze_response* g, void* user) {
    float x, y;
    skyle_gaze_get_smoothed(g, &x, &y);   // recommended: use smoothed values
    printf("gaze: %.1f, %.1f\n", x, y);
}

static void on_state(skyle_client* c, skyle_connection_state old_s,
                     skyle_connection_state new_s, void* user) {
    printf("state: %s -> %s\n",
           skyle_state_to_string(old_s), skyle_state_to_string(new_s));
}

int main(void) {
    skyle_client* client = skyle_client_get_instance();

    // Phase 1: transport (see "Transport configuration" for desktop helpers)
    skyle_transport_config transport = {
        .transport_write     = my_write,
        .transport_read      = my_read,
        .transport_user_data = my_ctx,
        .usb_device_check    = my_device_check,
    };
    skyle_client_set_transport(client, &transport);

    // Phase 2: callbacks
    skyle_callback_config callbacks = {
        .on_gaze         = on_gaze,
        .on_state_change = on_state,
        .user_data       = my_app_ctx,
    };
    skyle_client_set_callbacks(client, &callbacks);

    skyle_client_connect(client);         // async handshake on background thread

    // ... once on_state reports SKYLE_STATE_LINK_SYNCED:
    skyle_client_enable_gaze(client, true);

    // ... run your app ...

    skyle_client_destroy(client);
    return 0;
}
```

---

## Lifecycle

```c
skyle_client* skyle_client_get_instance(void);
skyle_result  skyle_client_set_transport(skyle_client* client,
                                     const skyle_transport_config* transport_config);
skyle_result  skyle_client_set_callbacks(skyle_client* client,
                                     const skyle_callback_config* callback_config);
void        skyle_client_destroy(skyle_client* client);
```

| Function | Description |
|----------|-------------|
| `skyle_client_get_instance` | Returns the singleton client (created on first call), or `NULL` on error. Call before configuring. |
| `skyle_client_set_transport` | Installs transport callbacks and **starts the background I/O + send threads**. `transport_config` must not be `NULL`. |
| `skyle_client_set_callbacks` | Installs message/system callbacks. `callback_config` must not be `NULL`. Set only the callbacks you need — leave the rest `NULL`. |
| `skyle_client_destroy` | Stops threads and tears down the client. |

`set_transport` and `set_callbacks` may be called in any order.

---

## Transport configuration

The transport layer provides raw bulk-endpoint I/O. You either use one of the
bundled desktop helpers or supply your own callbacks (Android, iOS, custom).

```c
typedef struct {
    skyle_transport_write_fn transport_write;   // REQUIRED
    skyle_transport_read_fn  transport_read;    // REQUIRED (background/read mode)
    void*                  transport_user_data;
    skyle_usb_device_check_fn usb_device_check; // may be NULL
    uint32_t connect_timeout_ms;
    uint32_t reconnect_interval_ms;
    bool     verbose;   // detailed debug logging
    bool     trace;     // per-packet trace logging (very verbose)
} skyle_transport_config;
```

**Callback signatures:**

```c
// Write bytes to the bulk OUT endpoint. Returns bytes written, or negative error.
typedef int  (*skyle_transport_write_fn)(const uint8_t* data, uint16_t length,
                                       void* user_data);

// Read bytes from the bulk IN endpoint. Returns bytes read (0 = timeout),
// or negative error.
typedef int  (*skyle_transport_read_fn)(uint8_t* buffer, uint16_t buffer_size,
                                      uint32_t timeout_ms, void* user_data);

// Report raw USB device presence (not protocol state). Returns true if present.
typedef bool (*skyle_usb_device_check_fn)(void* user_data);
```

### Desktop transport helpers

On desktop platforms the library ships ready-made USB transports, so you don't
have to implement the callbacks yourself.

**Windows (WinUSB)** — `#include <skylelib/skyle_transport_usb.h>`

```c
skyle_transport_usb* skyle_transport_usb_create(const skyle_transport_usb_config* config);
void               skyle_transport_usb_destroy(skyle_transport_usb* transport);
int                skyle_transport_usb_write(const uint8_t*, uint16_t, void*);
int                skyle_transport_usb_read(uint8_t*, uint16_t, uint32_t, void*);
bool               skyle_transport_usb_is_connected(const skyle_transport_usb*);
bool               skyle_transport_usb_device_exists(const skyle_transport_usb_config*);
skyle_usb_device_check_fn skyle_transport_usb_get_check_callback(void);
```

**macOS (IOKit)** — `#include <skylelib/skyle_transport_iokit.h>`

```c
skyle_transport_iokit* skyle_transport_iokit_create(const skyle_transport_iokit_config* config);
void                 skyle_transport_iokit_destroy(skyle_transport_iokit* transport);
int                  skyle_transport_iokit_write(const uint8_t*, uint16_t, void*);
int                  skyle_transport_iokit_read(uint8_t*, uint16_t, uint32_t, void*);
bool                 skyle_transport_iokit_is_connected(const skyle_transport_iokit*);
skyle_usb_device_check_fn skyle_transport_iokit_get_check_callback(void);
```

Both config structs share the same shape:

```c
typedef struct {
    uint16_t vendor_id;   // 0x3729 for Skyle
    uint16_t product_id;  // 0x7333 for Skyle
    uint32_t timeout_ms;
    bool     verbose;
} skyle_transport_usb_config;   // (and skyle_transport_iokit_config)
```

Wiring a desktop helper into the client:

```c
skyle_transport_usb* usb = skyle_transport_usb_create(&usb_cfg);
skyle_transport_config t = {
    .transport_write     = skyle_transport_usb_write,
    .transport_read      = skyle_transport_usb_read,
    .transport_user_data = usb,
    .usb_device_check    = skyle_transport_usb_get_check_callback(),
};
skyle_client_set_transport(client, &t);
```

On Android and iOS you implement the callbacks over the platform USB / External
Accessory APIs. iOS additionally has a [push-based API](#push-based-api-ios) that
avoids a background read thread.

---

## Callback configuration

```c
typedef struct {
    skyle_gaze_callback                 on_gaze;
    skyle_positioning_callback          on_positioning;
    skyle_version_callback              on_version;
    skyle_control_callback              on_control;
    skyle_calibration_point_callback    on_calibration_point;
    skyle_calibration_progress_callback on_calibration_progress;
    skyle_calibration_paused_callback   on_calibration_paused;
    skyle_calibration_finished_callback on_calibration_finished;
    skyle_calibration_aborted_callback  on_calibration_aborted;
    skyle_video_callback                on_video;
    skyle_file_status_callback          on_file_status;
    skyle_logging_callback              on_logging;
    skyle_state_callback                on_state_change;
    skyle_error_callback                on_error;
    void*                             user_data;   // passed to every callback
} skyle_callback_config;
```

Every callback receives the `skyle_client*` and your `user_data`. All are invoked
on the background I/O thread.

| Callback | Fired when |
|----------|-----------|
| `on_gaze` | Each gaze frame (`skyle_gaze_response`). |
| `on_positioning` | Each positioning frame (`skyle_positioning_response`). |
| `on_version` | Version/heartbeat response (`skyle_version_response`). |
| `on_control` | Device control state changed (`skyle_control_message`). |
| `on_calibration_point` | Device asks you to show the next point (`skyle_next_calibration_point`). |
| `on_calibration_progress` | Point-collection progress 0–100% (`skyle_collecting_calibration_points`). |
| `on_calibration_paused` | Device paused point collection. |
| `on_calibration_finished` | Calibration completed with quality data (`skyle_finished_calibration`). |
| `on_calibration_aborted` | Device aborted a running calibration (timeout/error). |
| `on_video` | A video frame finished chunked reassembly (`skyle_video_response`). `pixel_data` is valid **only during the call** — copy it to keep it. |
| `on_file_status` | Progress/success/failure of an upload (`skyle_file_status_response`). |
| `on_logging` | A device log line (`skyle_logging_response`). `message` is valid only during the call. |
| `on_state_change` | Connection state transition (`old_state` → `new_state`). |
| `on_error` | An error occurred (`skyle_result` + message string). |

---

## Connection management

```c
skyle_result           skyle_client_connect(skyle_client* client);
skyle_result           skyle_client_disconnect(skyle_client* client);
bool                 skyle_client_is_connected(const skyle_client* client);
skyle_connection_state skyle_client_get_state(const skyle_client* client);
uint32_t             skyle_client_get_packet_count(const skyle_client* client);
bool                 skyle_client_check_usb_device(const skyle_client* client);
void                 skyle_client_set_log_function(void (*log_func)(const char* fmt, ...));
```

| Function | Description |
|----------|-------------|
| `skyle_client_connect` | Starts the iAP2 + EAP handshake. Your transport must be ready to read/write. Returns immediately; watch `on_state_change` for `SKYLE_STATE_LINK_SYNCED`. |
| `skyle_client_disconnect` | Resets protocol state. Does **not** touch your transport — you own the endpoint lifecycle. |
| `skyle_client_is_connected` | `true` once the EAP link is up. |
| `skyle_client_get_state` | Current `skyle_connection_state`. |
| `skyle_client_get_packet_count` | Total successfully-parsed iAP2 packets (protocol level, before EAP parsing). Handy for liveness checks. |
| `skyle_client_check_usb_device` | Raw USB presence via your `usb_device_check` callback (not the protocol state). |
| `skyle_client_set_log_function` | Redirect verbose/debug output to your own logger instead of `printf`. Pass `NULL` to restore default. |

### Connection states

```
DISCONNECTED → WAITING_PING → HANDSHAKE_SENT → WAITING_SYN →
SYN_ACK_SENT → CONNECTED → WAITING_START_EAP_ACK → LINK_SYNCED
                                                       ↓
                                                     ERROR
```

Only send stream/control messages in `SKYLE_STATE_LINK_SYNCED`.

---

## Streaming & message API

All of these are safe to call once the link is `LINK_SYNCED`. The `enable`
functions toggle a device-side stream; responses arrive via the matching
callback.

```c
skyle_result skyle_client_request_version(skyle_client* client);
skyle_result skyle_client_enable_gaze(skyle_client* client, bool enable);
skyle_result skyle_client_enable_positioning(skyle_client* client, bool enable);
skyle_result skyle_client_enable_control(skyle_client* client, bool enable);
skyle_result skyle_client_send_control(skyle_client* client, const skyle_control_message* message);
skyle_result skyle_client_send_display_info(skyle_client* client, const skyle_set_display_info* info);
skyle_result skyle_client_enable_logging(skyle_client* client, bool enable);
skyle_result skyle_client_enable_video(skyle_client* client, bool enable);
```

| Function | Description |
|----------|-------------|
| `skyle_client_request_version` | Request a one-off version response. (The library also sends this as a heartbeat every 500 ms.) |
| `skyle_client_enable_gaze` | Start/stop the gaze stream → `on_gaze`. |
| `skyle_client_enable_positioning` | Start/stop the positioning stream → `on_positioning`. |
| `skyle_client_enable_control` | Start/stop the control stream → `on_control`. On enable the device replies with the current state. |
| `skyle_client_send_control` | Push new device settings (tracking mode, filters, pause, HID, …). Bidirectional message. |
| `skyle_client_send_display_info` | Tell the device your display resolution (px) and physical size (mm). Fire-and-forget. |
| `skyle_client_enable_logging` | Start/stop the device log stream → `on_logging`. |
| `skyle_client_enable_video` | Start/stop the video stream → `on_video` (delivered via chunked reassembly). |

---

## Calibration

```c
skyle_result skyle_client_start_calibration(skyle_client* client,
                                        const skyle_calibration_config* config);
skyle_result skyle_client_collect_calibration_points(skyle_client* client);
skyle_result skyle_client_abort_calibration(skyle_client* client);
```

Typical flow:

1. `skyle_client_start_calibration()` with an `skyle_calibration_config` (number of
   points, optional custom coordinates, screen resolution + physical size).
2. For each point, `on_calibration_point` fires — show the target, then call
   `skyle_client_collect_calibration_points()` when the user is fixating.
3. `on_calibration_progress` reports 0–100% for the current point;
   `on_calibration_paused` may fire between points.
4. `on_calibration_finished` delivers an `skyle_finished_calibration` with per-eye
   quality points. **Free it with `skyle_free_finished_calibration()`** when done.
5. `skyle_client_abort_calibration()` cancels; the device may also abort on its own
   (→ `on_calibration_aborted`).

Use `skyle_calibration_get_average_quality()` to reduce the result to a single
0.0–1.0 score.

---

## File upload

```c
skyle_result skyle_client_upload_file(skyle_client* client, const char* path,
                                  uint8_t* data, uint32_t data_len,
                                  const uint8_t* sha256_hash);
skyle_result skyle_client_cancel_upload(skyle_client* client);
bool       skyle_client_is_upload_running(const skyle_client* client);
```

`skyle_client_upload_file` streams a whole file to `path` on the device on a
dedicated upload thread and returns immediately; progress and completion arrive
via `on_file_status`.

> **Ownership:** `data` must be `malloc`'d and ownership is **transferred** — the
> upload thread frees it when done. On an error return the caller still owns
> `data` (it is not freed). `sha256_hash` is an optional 32-byte verification
> hash, or `NULL`.

`skyle_client_cancel_upload` stops at the next chunk boundary and fires
`on_file_status` with a `FAILED` status; it is safe to call when no upload is
running.

---

## Push-based API (iOS)

For platforms where the OS owns the read loop (iOS ExternalAccessory), use the
push model instead of `set_transport`: no background read thread is started, and
you feed received bytes in yourself.

```c
skyle_result skyle_client_set_push_transport(skyle_client* client,
                                         skyle_transport_write_fn write_fn,
                                         skyle_usb_device_check_fn device_check_fn,
                                         void* user_data);
skyle_result skyle_client_process_received_data(skyle_client* client,
                                            const uint8_t* data, uint16_t length);
skyle_result skyle_client_tick(skyle_client* client);
```

| Function | Description |
|----------|-------------|
| `skyle_client_set_push_transport` | Installs the write + device-check callbacks and starts the send thread (no read thread). `write_fn` required; `device_check_fn` may be `NULL`. |
| `skyle_client_process_received_data` | Feed raw bytes as they arrive; the client parses frames, handles the handshake, sends ACKs and dispatches callbacks. |
| `skyle_client_tick` | Call ~every 200 ms to drive heartbeat (version every 500 ms), idle-timeout (2500 ms), and auto-reconnect. |

---

## Data structures

All message structures begin with an `skyle_message_header` (populated by the
library) and use big-endian-decoded native types. Multi-byte numeric fields have
already been byte-swapped for you.

### Common types (`eap/skyle_types.h`)

```c
typedef struct { float x, y; }                       skyle_pointf;      //  8 bytes
typedef struct { float width, height; }              skyle_sizef;       //  8 bytes
typedef struct { uint16_t width, height; }           skyle_sizeu;       //  4 bytes
typedef struct { float top, left, bottom, right; }   skyle_rectf;       // 16 bytes
typedef struct { uint16_t top, left, bottom, right; } skyle_rectu;      //  8 bytes
typedef struct { skyle_pointf center; skyle_sizef size; float angle; } skyle_rotated_rect; // 20 bytes

typedef struct {
    uint16_t message_type;   // e.g. 0x00D1 for gaze response
    uint16_t payload_length;
    int64_t  timestamp_ms;   // Unix ms, from the extended header (responses)
    bool     has_timestamp;
} skyle_message_header;
```

Big-endian helpers (inline): `skyle_read_float_be`, `skyle_write_float_be`,
`skyle_read_uint16_be`, `skyle_write_uint16_be`, `skyle_write_uint32_be`, plus
`*_from_bytes` / `*_to_bytes` for each point/size/rect type.

### Gaze (`eap/gaze/gaze_messages.h`)

```c
typedef struct {
    skyle_pointf raw;        // raw gaze coordinates
    skyle_pointf smoothed;   // smoothed coordinates (use these for display)
    uint8_t    type;       // skyle_eye_movement_type
} skyle_complex_gaze;        // 17 bytes

typedef struct {
    skyle_message_header header;
    skyle_complex_gaze   left;    // left eye
    skyle_complex_gaze   right;   // right eye
    skyle_complex_gaze   both;    // combined
} skyle_gaze_response;       // 51-byte payload
```

Helpers: `skyle_gaze_get_smoothed(resp, &x, &y)`, `skyle_gaze_get_raw(...)`,
`skyle_gaze_is_valid(resp)`. **Always prefer the smoothed values.**

### Positioning (`eap/positioning/positioning_messages.h`)

A full face/eye tree (384-byte payload). Coordinates are in **camera image**
space (not screen space).

```c
typedef struct { skyle_pointf center; skyle_rectf bounding_rect; skyle_rotated_rect ellipse; } skyle_complex_feature; // 44 B
typedef struct { skyle_pointf center, top, left, right, bottom; float distance_mm; }       skyle_complex_iris;    // 44 B
typedef struct {
    skyle_rectu           bounding_rect;
    skyle_complex_feature pupil, left_glint, right_glint;
    skyle_complex_iris    iris;
} skyle_complex_eye;         // 184 B
typedef struct { skyle_complex_eye left, right; } skyle_complex_eyes;              // 368 B
typedef struct { skyle_rectf bounding_rect; skyle_complex_eyes eyes; } skyle_complex_face; // 384 B

typedef struct {
    skyle_message_header header;
    skyle_complex_face   face;
} skyle_positioning_response;
```

Helpers: `skyle_positioning_get_face_center`, `skyle_positioning_get_face_size`,
`skyle_positioning_has_face`, `skyle_positioning_has_left_pupil`,
`skyle_positioning_has_right_pupil`, `skyle_positioning_get_pupil_distance`.

### Version (`eap/version/version_messages.h`)

```c
typedef struct {
    skyle_message_header header;
    char     firmware[32];          // UTF-8, may not be NUL-terminated
    uint64_t serial;
    bool     is_demo_device;
    uint8_t  device_type;
    uint8_t  device_platform;
    uint8_t  device_generation;
    char     protocol_version[32];  // EAP protocol version; empty on old firmware
} skyle_version_response;   // 76-byte payload
```

Use `skyle_version_get_firmware_string(resp, buf, sizeof buf)` and
`skyle_version_get_protocol_version_string(...)` to get NUL-terminated copies
(buffer ≥ 33 bytes recommended).

### Control (`eap/control/control_messages.h`)

```c
typedef struct {
    skyle_message_header header;
    bool    is_standby_enabled;
    bool    is_auto_pause_enabled;
    bool    is_pause_enabled;
    uint8_t tracking_mode;            // skyle_tracking_mode
    uint8_t gaze_filter;              // 0–255
    uint8_t fixation_filter;          // 0–255
    bool    is_assistive_touch_enabled;
    bool    show_tracking_details;
    bool    is_hid_enabled;
    bool    is_ethernet_enabled;
} skyle_control_message;   // 10-byte payload

typedef struct {
    skyle_sizeu resolution;   // pixels
    skyle_sizef size_mm;      // millimeters
} skyle_set_display_info;     // 12-byte payload
```

Helpers: `skyle_control_is_tracking_active(ctrl)`, `skyle_tracking_mode_name(mode)`.

### Calibration (`eap/calibration/calibration_messages.h`)

```c
typedef struct {
    uint16_t    points_count;
    uint8_t*    points;             // point indices, e.g. [0,1,2,3,4]
    uint16_t    coordinates_count;
    skyle_pointf* coordinates;        // custom coords, or NULL for automatic
    skyle_sizeu   resolution;         // screen pixels
    skyle_sizef   size;               // physical size in mm
    bool        improve;            // improve existing vs. new calibration
} skyle_calibration_config;

typedef struct { skyle_message_header header; uint8_t index; skyle_pointf point; }  skyle_next_calibration_point;
typedef struct { skyle_message_header header; uint8_t index; uint8_t progress; }  skyle_collecting_calibration_points;

typedef struct {
    uint8_t    index;
    skyle_pointf accuracy;   // offset to the calibration point
    float      precision;  // precision radius
    uint8_t    quality;    // 0–255
} skyle_quality_point;       // 14 bytes

typedef struct {
    skyle_message_header header;
    uint16_t           left_count;
    skyle_quality_point* left;    // free with skyle_free_finished_calibration()
    uint16_t           right_count;
    skyle_quality_point* right;
} skyle_finished_calibration;
```

Free dynamic arrays with `skyle_free_finished_calibration()` (and
`skyle_free_configure_calibration()` if you built a config with heap arrays).

### Video (`eap/video/video_messages.h`)

```c
typedef struct {
    uint16_t       width;
    uint16_t       height;
    uint8_t        channels;
    const uint8_t* pixel_data;         // valid ONLY during the callback — copy to keep
    uint32_t       pixel_data_length;  // width * height * channels
} skyle_video_response;
```

### File status (`eap/file/file_messages.h`)

```c
typedef struct {
    skyle_message_header   header;
    skyle_file_status_code status;      // SUCCESS / PROGRESS / FAILED
    uint16_t             progress;    // 0–100 when PROGRESS
    char                 error_message[256];  // when FAILED
    uint16_t             error_message_length;
} skyle_file_status_response;
```

Constants: `SKYLE_FILE_MAX_CHUNK_DATA` (4048), `SKYLE_FILE_MAX_CHUNKS`,
`SKYLE_FILE_MAX_SIZE`.

### Logging (`eap/logging/logging_messages.h`)

```c
typedef struct {
    skyle_message_header header;
    skyle_log_level      level;
    char               message[512];   // NUL-terminated UTF-8
    uint16_t           message_len;
} skyle_logging_response;
```

Helper: `skyle_log_level_name(level)`.

---

## Enumerations & return codes

### `skyle_result` — return codes

| Value | Meaning |
|-------|---------|
| `SKYLE_OK` (0) | Success |
| `SKYLE_ERROR_NOT_FOUND` (−1) | Device/resource not found |
| `SKYLE_ERROR_TIMEOUT` (−2) | Operation timed out |
| `SKYLE_ERROR_INVALID_STATE` (−3) | Not valid in the current state (e.g. sending before `LINK_SYNCED`) |
| `SKYLE_ERROR_COMMUNICATION` (−4) | Transport/I/O error |
| `SKYLE_ERROR_PARSE` (−5) | Malformed data |
| `SKYLE_ERROR_MEMORY` (−6) | Allocation failure |

### `skyle_connection_state`

`SKYLE_STATE_DISCONNECTED`, `WAITING_PING`, `HANDSHAKE_SENT`, `WAITING_SYN`,
`SYN_ACK_SENT`, `CONNECTED`, `WAITING_START_EAP_ACK`, `LINK_SYNCED`, `ERROR`.

### `skyle_eye_movement_type`

`SKYLE_EYE_MOVEMENT_FIXATION` (0), `SKYLE_EYE_MOVEMENT_SACCADE` (1),
`SKYLE_EYE_MOVEMENT_UNKNOWN` (2).

### `skyle_tracking_mode`

`SKYLE_TRACKING_MODE_BINOCULAR` (0), `SKYLE_TRACKING_MODE_LEFT` (1),
`SKYLE_TRACKING_MODE_RIGHT` (2).

### `skyle_file_status_code`

`SKYLE_FILE_STATUS_SUCCESS` (0x0000), `SKYLE_FILE_STATUS_PROGRESS` (0x0001),
`SKYLE_FILE_STATUS_FAILED` (0x0002).

### `skyle_log_level`

`SKYLE_LOG_TRACE` (0), `DEBUG` (1), `INFORMATION` (2), `WARNING` (3), `ERROR` (4),
`CRITICAL` (5), `NONE` (6).

### `skyle_message_type` (selected)

| Category | Request | Response | Payload |
|----------|---------|----------|---------|
| Gaze | `0x00D0` | `0x00D1` | 51 bytes (3× complex gaze) |
| Positioning | `0x00B0` | `0x00B1` | 384 bytes (face + eyes) |
| Version | `0x00F0` | `0x00F1` | 76 bytes (firmware, serial) |
| Control | `0x00E0` | `0x00E1` | 10 bytes (bidirectional) |
| Set display info | `0x00E2` | — | 12 bytes (App → Device) |
| Calibration | `0x00C0`–`0x00C6` | | Variable (multi-step workflow) |
| Video | `0x0050` | `0x0051` | Variable (chunked frames) |
| File | `0x00A0`–`0x00A3` | | Variable (chunked upload) |
| Logging | `0x0100` | `0x0101` | Variable |
| Chunked (generic) | `0x0010`–`0x0013` | | Variable |

Helpers: `skyle_message_type_name(t)`, `skyle_message_type_is_request(t)`,
`skyle_message_type_is_response(t)`.

---

## Utility helpers

```c
const char* skyle_result_to_string(skyle_result result);
const char* skyle_state_to_string(skyle_connection_state state);
const char* skylelib_version(void);   // from <skylelib/skylelib_version.h>
```

---

## Threading model

`skyle_client_set_transport()` starts:

- a **background I/O thread** that reads USB, parses iAP2/EAP packets, drives the
  handshake and heartbeat, and invokes your callbacks;
- a **send thread** that drains a dual-tier priority send queue (ACKs/control
  first, bulk file data with anti-starvation).

A dedicated **upload thread** is spawned on demand by
`skyle_client_upload_file()`.

You can stop/query the background thread explicitly (mainly for shutdown):

```c
skyle_result skyle_client_stop_background(skyle_client* client);
bool       skyle_client_is_background_running(const skyle_client* client);
```

> **All callbacks run on the background I/O thread.** Copy any data you need to
> retain (notably `skyle_video_response::pixel_data` and
> `skyle_logging_response::message`, which are valid only for the duration of the
> call), and marshal to your UI/main thread before touching UI state.

---

## Versioning

skylelib uses plain SemVer. The version is the release tag (`vX.Y.Z`), is baked
into `<skylelib/skylelib_version.h>` as `SKYLELIB_VERSION_STRING` /
`SKYLELIB_VERSION_MAJOR|MINOR|PATCH`, and is queryable at runtime:

```c
printf("skylelib %s\n", skylelib_version());
```

---

Questions or device access: **support@eyev.de**.
