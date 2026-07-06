# skylelib — Public API Reference

**skylelib** is eyeV's cross-platform C17 library for communicating with the
**Skyle** eye-tracker (VID `0x3729`, PID `0x7333`) over USB. It speaks Apple's
iAP2 link protocol with the EAP (External Accessory Protocol) message layer on
top, and exposes a small, opaque C API with typed callbacks for gaze,
positioning, video, calibration and more.

This document describes the **public API** — everything shipped in the
`include/skylelib/` headers bundled with each
[release](https://github.com/eyev-de/skylelib/releases). All symbols are
annotated with `SKYLELIB_API` (the export macro) and declared `extern "C"`, so
the library is directly consumable from C, C++, and via FFI/P-Invoke bindings
(the [examples](README.md) use .NET, Swift and Dart).

- **Main header:** `#include <skylelib/eap_client.h>` — pulls in every message
  type and structure you need.
- **Language:** C17, C ABI. Opaque `eap_client` handle.
- **Byte order:** all wire data is **big-endian**. The library handles this for
  you; if you parse payloads yourself, use the `eap_read_*_be()` helpers in
  `eap/eap_types.h` — never `memcpy` multi-byte values.

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
`eap_client_get_instance()` returns it (creating it on first call). You do not
allocate it yourself.

**Two-phase configuration.** Configure the client in two independent steps, in
either order:

1. **Transport** (`eap_client_set_transport`) — platform-specific USB read/write
   callbacks. Setting this starts the background I/O and send threads.
2. **Callbacks** (`eap_client_set_callbacks`) — your application-level handlers
   for gaze, positioning, state changes, etc.

**Automatic handshake.** After `eap_client_connect()`, the library runs the full
iAP2 + EAP handshake on its background thread and drives a 9-state connection
machine. You only send stream/control messages once the state reaches
`EAP_STATE_LINK_SYNCED`.

**Callbacks run on the I/O thread.** All message callbacks are invoked from the
library's background thread. Marshal to your UI/main thread before touching UI
state.

---

## Quick start

```c
#include <skylelib/eap_client.h>

static void on_gaze(eap_client* c, const eap_gaze_response* g, void* user) {
    float x, y;
    eap_gaze_get_smoothed(g, &x, &y);   // recommended: use smoothed values
    printf("gaze: %.1f, %.1f\n", x, y);
}

static void on_state(eap_client* c, eap_connection_state old_s,
                     eap_connection_state new_s, void* user) {
    printf("state: %s -> %s\n",
           eap_state_to_string(old_s), eap_state_to_string(new_s));
}

int main(void) {
    eap_client* client = eap_client_get_instance();

    // Phase 1: transport (see "Transport configuration" for desktop helpers)
    eap_transport_config transport = {
        .transport_write     = my_write,
        .transport_read      = my_read,
        .transport_user_data = my_ctx,
        .usb_device_check    = my_device_check,
    };
    eap_client_set_transport(client, &transport);

    // Phase 2: callbacks
    eap_callback_config callbacks = {
        .on_gaze         = on_gaze,
        .on_state_change = on_state,
        .user_data       = my_app_ctx,
    };
    eap_client_set_callbacks(client, &callbacks);

    eap_client_connect(client);         // async handshake on background thread

    // ... once on_state reports EAP_STATE_LINK_SYNCED:
    eap_client_enable_gaze(client, true);

    // ... run your app ...

    eap_client_destroy(client);
    return 0;
}
```

---

## Lifecycle

```c
eap_client* eap_client_get_instance(void);
eap_result  eap_client_set_transport(eap_client* client,
                                     const eap_transport_config* transport_config);
eap_result  eap_client_set_callbacks(eap_client* client,
                                     const eap_callback_config* callback_config);
void        eap_client_destroy(eap_client* client);
```

| Function | Description |
|----------|-------------|
| `eap_client_get_instance` | Returns the singleton client (created on first call), or `NULL` on error. Call before configuring. |
| `eap_client_set_transport` | Installs transport callbacks and **starts the background I/O + send threads**. `transport_config` must not be `NULL`. |
| `eap_client_set_callbacks` | Installs message/system callbacks. `callback_config` must not be `NULL`. Set only the callbacks you need — leave the rest `NULL`. |
| `eap_client_destroy` | Stops threads and tears down the client. |

`set_transport` and `set_callbacks` may be called in any order.

---

## Transport configuration

The transport layer provides raw bulk-endpoint I/O. You either use one of the
bundled desktop helpers or supply your own callbacks (Android, iOS, custom).

```c
typedef struct {
    eap_transport_write_fn transport_write;   // REQUIRED
    eap_transport_read_fn  transport_read;    // REQUIRED (background/read mode)
    void*                  transport_user_data;
    eap_usb_device_check_fn usb_device_check; // may be NULL
    uint32_t connect_timeout_ms;
    uint32_t reconnect_interval_ms;
    bool     verbose;   // detailed debug logging
    bool     trace;     // per-packet trace logging (very verbose)
} eap_transport_config;
```

**Callback signatures:**

```c
// Write bytes to the bulk OUT endpoint. Returns bytes written, or negative error.
typedef int  (*eap_transport_write_fn)(const uint8_t* data, uint16_t length,
                                       void* user_data);

// Read bytes from the bulk IN endpoint. Returns bytes read (0 = timeout),
// or negative error.
typedef int  (*eap_transport_read_fn)(uint8_t* buffer, uint16_t buffer_size,
                                      uint32_t timeout_ms, void* user_data);

// Report raw USB device presence (not protocol state). Returns true if present.
typedef bool (*eap_usb_device_check_fn)(void* user_data);
```

### Desktop transport helpers

On desktop platforms the library ships ready-made USB transports, so you don't
have to implement the callbacks yourself.

**Windows (WinUSB)** — `#include <skylelib/eap_transport_usb.h>`

```c
eap_transport_usb* eap_transport_usb_create(const eap_transport_usb_config* config);
void               eap_transport_usb_destroy(eap_transport_usb* transport);
int                eap_transport_usb_write(const uint8_t*, uint16_t, void*);
int                eap_transport_usb_read(uint8_t*, uint16_t, uint32_t, void*);
bool               eap_transport_usb_is_connected(const eap_transport_usb*);
bool               eap_transport_usb_device_exists(const eap_transport_usb_config*);
eap_usb_device_check_fn eap_transport_usb_get_check_callback(void);
```

**macOS (IOKit)** — `#include <skylelib/eap_transport_iokit.h>`

```c
eap_transport_iokit* eap_transport_iokit_create(const eap_transport_iokit_config* config);
void                 eap_transport_iokit_destroy(eap_transport_iokit* transport);
int                  eap_transport_iokit_write(const uint8_t*, uint16_t, void*);
int                  eap_transport_iokit_read(uint8_t*, uint16_t, uint32_t, void*);
bool                 eap_transport_iokit_is_connected(const eap_transport_iokit*);
eap_usb_device_check_fn eap_transport_iokit_get_check_callback(void);
```

Both config structs share the same shape:

```c
typedef struct {
    uint16_t vendor_id;   // 0x3729 for Skyle
    uint16_t product_id;  // 0x7333 for Skyle
    uint32_t timeout_ms;
    bool     verbose;
} eap_transport_usb_config;   // (and eap_transport_iokit_config)
```

Wiring a desktop helper into the client:

```c
eap_transport_usb* usb = eap_transport_usb_create(&usb_cfg);
eap_transport_config t = {
    .transport_write     = eap_transport_usb_write,
    .transport_read      = eap_transport_usb_read,
    .transport_user_data = usb,
    .usb_device_check    = eap_transport_usb_get_check_callback(),
};
eap_client_set_transport(client, &t);
```

On Android and iOS you implement the callbacks over the platform USB / External
Accessory APIs. iOS additionally has a [push-based API](#push-based-api-ios) that
avoids a background read thread.

---

## Callback configuration

```c
typedef struct {
    eap_gaze_callback                 on_gaze;
    eap_positioning_callback          on_positioning;
    eap_version_callback              on_version;
    eap_control_callback              on_control;
    eap_calibration_point_callback    on_calibration_point;
    eap_calibration_progress_callback on_calibration_progress;
    eap_calibration_paused_callback   on_calibration_paused;
    eap_calibration_finished_callback on_calibration_finished;
    eap_calibration_aborted_callback  on_calibration_aborted;
    eap_video_callback                on_video;
    eap_file_status_callback          on_file_status;
    eap_logging_callback              on_logging;
    eap_state_callback                on_state_change;
    eap_error_callback                on_error;
    void*                             user_data;   // passed to every callback
} eap_callback_config;
```

Every callback receives the `eap_client*` and your `user_data`. All are invoked
on the background I/O thread.

| Callback | Fired when |
|----------|-----------|
| `on_gaze` | Each gaze frame (`eap_gaze_response`). |
| `on_positioning` | Each positioning frame (`eap_positioning_response`). |
| `on_version` | Version/heartbeat response (`eap_version_response`). |
| `on_control` | Device control state changed (`eap_control_message`). |
| `on_calibration_point` | Device asks you to show the next point (`eap_next_calibration_point`). |
| `on_calibration_progress` | Point-collection progress 0–100% (`eap_collecting_calibration_points`). |
| `on_calibration_paused` | Device paused point collection. |
| `on_calibration_finished` | Calibration completed with quality data (`eap_finished_calibration`). |
| `on_calibration_aborted` | Device aborted a running calibration (timeout/error). |
| `on_video` | A video frame finished chunked reassembly (`eap_video_response`). `pixel_data` is valid **only during the call** — copy it to keep it. |
| `on_file_status` | Progress/success/failure of an upload (`eap_file_status_response`). |
| `on_logging` | A device log line (`eap_logging_response`). `message` is valid only during the call. |
| `on_state_change` | Connection state transition (`old_state` → `new_state`). |
| `on_error` | An error occurred (`eap_result` + message string). |

---

## Connection management

```c
eap_result           eap_client_connect(eap_client* client);
eap_result           eap_client_disconnect(eap_client* client);
bool                 eap_client_is_connected(const eap_client* client);
eap_connection_state eap_client_get_state(const eap_client* client);
uint32_t             eap_client_get_packet_count(const eap_client* client);
bool                 eap_client_check_usb_device(const eap_client* client);
void                 eap_client_set_log_function(void (*log_func)(const char* fmt, ...));
```

| Function | Description |
|----------|-------------|
| `eap_client_connect` | Starts the iAP2 + EAP handshake. Your transport must be ready to read/write. Returns immediately; watch `on_state_change` for `EAP_STATE_LINK_SYNCED`. |
| `eap_client_disconnect` | Resets protocol state. Does **not** touch your transport — you own the endpoint lifecycle. |
| `eap_client_is_connected` | `true` once the EAP link is up. |
| `eap_client_get_state` | Current `eap_connection_state`. |
| `eap_client_get_packet_count` | Total successfully-parsed iAP2 packets (protocol level, before EAP parsing). Handy for liveness checks. |
| `eap_client_check_usb_device` | Raw USB presence via your `usb_device_check` callback (not the protocol state). |
| `eap_client_set_log_function` | Redirect verbose/debug output to your own logger instead of `printf`. Pass `NULL` to restore default. |

### Connection states

```
DISCONNECTED → WAITING_PING → HANDSHAKE_SENT → WAITING_SYN →
SYN_ACK_SENT → CONNECTED → WAITING_START_EAP_ACK → LINK_SYNCED
                                                       ↓
                                                     ERROR
```

Only send stream/control messages in `EAP_STATE_LINK_SYNCED`.

---

## Streaming & message API

All of these are safe to call once the link is `LINK_SYNCED`. The `enable`
functions toggle a device-side stream; responses arrive via the matching
callback.

```c
eap_result eap_client_request_version(eap_client* client);
eap_result eap_client_enable_gaze(eap_client* client, bool enable);
eap_result eap_client_enable_positioning(eap_client* client, bool enable);
eap_result eap_client_enable_control(eap_client* client, bool enable);
eap_result eap_client_send_control(eap_client* client, const eap_control_message* message);
eap_result eap_client_send_display_info(eap_client* client, const eap_set_display_info* info);
eap_result eap_client_enable_logging(eap_client* client, bool enable);
eap_result eap_client_enable_video(eap_client* client, bool enable);
```

| Function | Description |
|----------|-------------|
| `eap_client_request_version` | Request a one-off version response. (The library also sends this as a heartbeat every 500 ms.) |
| `eap_client_enable_gaze` | Start/stop the gaze stream → `on_gaze`. |
| `eap_client_enable_positioning` | Start/stop the positioning stream → `on_positioning`. |
| `eap_client_enable_control` | Start/stop the control stream → `on_control`. On enable the device replies with the current state. |
| `eap_client_send_control` | Push new device settings (tracking mode, filters, pause, HID, …). Bidirectional message. |
| `eap_client_send_display_info` | Tell the device your display resolution (px) and physical size (mm). Fire-and-forget. |
| `eap_client_enable_logging` | Start/stop the device log stream → `on_logging`. |
| `eap_client_enable_video` | Start/stop the video stream → `on_video` (delivered via chunked reassembly). |

---

## Calibration

```c
eap_result eap_client_start_calibration(eap_client* client,
                                        const eap_calibration_config* config);
eap_result eap_client_collect_calibration_points(eap_client* client);
eap_result eap_client_abort_calibration(eap_client* client);
```

Typical flow:

1. `eap_client_start_calibration()` with an `eap_calibration_config` (number of
   points, optional custom coordinates, screen resolution + physical size).
2. For each point, `on_calibration_point` fires — show the target, then call
   `eap_client_collect_calibration_points()` when the user is fixating.
3. `on_calibration_progress` reports 0–100% for the current point;
   `on_calibration_paused` may fire between points.
4. `on_calibration_finished` delivers an `eap_finished_calibration` with per-eye
   quality points. **Free it with `eap_free_finished_calibration()`** when done.
5. `eap_client_abort_calibration()` cancels; the device may also abort on its own
   (→ `on_calibration_aborted`).

Use `eap_calibration_get_average_quality()` to reduce the result to a single
0.0–1.0 score.

---

## File upload

```c
eap_result eap_client_upload_file(eap_client* client, const char* path,
                                  uint8_t* data, uint32_t data_len,
                                  const uint8_t* sha256_hash);
eap_result eap_client_cancel_upload(eap_client* client);
bool       eap_client_is_upload_running(const eap_client* client);
```

`eap_client_upload_file` streams a whole file to `path` on the device on a
dedicated upload thread and returns immediately; progress and completion arrive
via `on_file_status`.

> **Ownership:** `data` must be `malloc`'d and ownership is **transferred** — the
> upload thread frees it when done. On an error return the caller still owns
> `data` (it is not freed). `sha256_hash` is an optional 32-byte verification
> hash, or `NULL`.

`eap_client_cancel_upload` stops at the next chunk boundary and fires
`on_file_status` with a `FAILED` status; it is safe to call when no upload is
running.

---

## Push-based API (iOS)

For platforms where the OS owns the read loop (iOS ExternalAccessory), use the
push model instead of `set_transport`: no background read thread is started, and
you feed received bytes in yourself.

```c
eap_result eap_client_set_push_transport(eap_client* client,
                                         eap_transport_write_fn write_fn,
                                         eap_usb_device_check_fn device_check_fn,
                                         void* user_data);
eap_result eap_client_process_received_data(eap_client* client,
                                            const uint8_t* data, uint16_t length);
eap_result eap_client_tick(eap_client* client);
```

| Function | Description |
|----------|-------------|
| `eap_client_set_push_transport` | Installs the write + device-check callbacks and starts the send thread (no read thread). `write_fn` required; `device_check_fn` may be `NULL`. |
| `eap_client_process_received_data` | Feed raw bytes as they arrive; the client parses frames, handles the handshake, sends ACKs and dispatches callbacks. |
| `eap_client_tick` | Call ~every 200 ms to drive heartbeat (version every 500 ms), idle-timeout (2500 ms), and auto-reconnect. |

---

## Data structures

All message structures begin with an `eap_message_header` (populated by the
library) and use big-endian-decoded native types. Multi-byte numeric fields have
already been byte-swapped for you.

### Common types (`eap/eap_types.h`)

```c
typedef struct { float x, y; }                       eap_pointf;      //  8 bytes
typedef struct { float width, height; }              eap_sizef;       //  8 bytes
typedef struct { uint16_t width, height; }           eap_sizeu;       //  4 bytes
typedef struct { float top, left, bottom, right; }   eap_rectf;       // 16 bytes
typedef struct { uint16_t top, left, bottom, right; } eap_rectu;      //  8 bytes
typedef struct { eap_pointf center; eap_sizef size; float angle; } eap_rotated_rect; // 20 bytes

typedef struct {
    uint16_t message_type;   // e.g. 0x00D1 for gaze response
    uint16_t payload_length;
    int64_t  timestamp_ms;   // Unix ms, from the extended header (responses)
    bool     has_timestamp;
} eap_message_header;
```

Big-endian helpers (inline): `eap_read_float_be`, `eap_write_float_be`,
`eap_read_uint16_be`, `eap_write_uint16_be`, `eap_write_uint32_be`, plus
`*_from_bytes` / `*_to_bytes` for each point/size/rect type.

### Gaze (`eap/gaze/gaze_messages.h`)

```c
typedef struct {
    eap_pointf raw;        // raw gaze coordinates
    eap_pointf smoothed;   // smoothed coordinates (use these for display)
    uint8_t    type;       // eap_eye_movement_type
} eap_complex_gaze;        // 17 bytes

typedef struct {
    eap_message_header header;
    eap_complex_gaze   left;    // left eye
    eap_complex_gaze   right;   // right eye
    eap_complex_gaze   both;    // combined
} eap_gaze_response;       // 51-byte payload
```

Helpers: `eap_gaze_get_smoothed(resp, &x, &y)`, `eap_gaze_get_raw(...)`,
`eap_gaze_is_valid(resp)`. **Always prefer the smoothed values.**

### Positioning (`eap/positioning/positioning_messages.h`)

A full face/eye tree (384-byte payload). Coordinates are in **camera image**
space (not screen space).

```c
typedef struct { eap_pointf center; eap_rectf bounding_rect; eap_rotated_rect ellipse; } eap_complex_feature; // 44 B
typedef struct { eap_pointf center, top, left, right, bottom; float distance_mm; }       eap_complex_iris;    // 44 B
typedef struct {
    eap_rectu           bounding_rect;
    eap_complex_feature pupil, left_glint, right_glint;
    eap_complex_iris    iris;
} eap_complex_eye;         // 184 B
typedef struct { eap_complex_eye left, right; } eap_complex_eyes;              // 368 B
typedef struct { eap_rectf bounding_rect; eap_complex_eyes eyes; } eap_complex_face; // 384 B

typedef struct {
    eap_message_header header;
    eap_complex_face   face;
} eap_positioning_response;
```

Helpers: `eap_positioning_get_face_center`, `eap_positioning_get_face_size`,
`eap_positioning_has_face`, `eap_positioning_has_left_pupil`,
`eap_positioning_has_right_pupil`, `eap_positioning_get_pupil_distance`.

### Version (`eap/version/version_messages.h`)

```c
typedef struct {
    eap_message_header header;
    char     firmware[32];          // UTF-8, may not be NUL-terminated
    uint64_t serial;
    bool     is_demo_device;
    uint8_t  device_type;
    uint8_t  device_platform;
    uint8_t  device_generation;
    char     protocol_version[32];  // EAP protocol version; empty on old firmware
} eap_version_response;   // 76-byte payload
```

Use `eap_version_get_firmware_string(resp, buf, sizeof buf)` and
`eap_version_get_protocol_version_string(...)` to get NUL-terminated copies
(buffer ≥ 33 bytes recommended).

### Control (`eap/control/control_messages.h`)

```c
typedef struct {
    eap_message_header header;
    bool    is_standby_enabled;
    bool    is_auto_pause_enabled;
    bool    is_pause_enabled;
    uint8_t tracking_mode;            // eap_tracking_mode
    uint8_t gaze_filter;              // 0–255
    uint8_t fixation_filter;          // 0–255
    bool    is_assistive_touch_enabled;
    bool    show_tracking_details;
    bool    is_hid_enabled;
    bool    is_ethernet_enabled;
} eap_control_message;   // 10-byte payload

typedef struct {
    eap_sizeu resolution;   // pixels
    eap_sizef size_mm;      // millimeters
} eap_set_display_info;     // 12-byte payload
```

Helpers: `eap_control_is_tracking_active(ctrl)`, `eap_tracking_mode_name(mode)`.

### Calibration (`eap/calibration/calibration_messages.h`)

```c
typedef struct {
    uint16_t    points_count;
    uint8_t*    points;             // point indices, e.g. [0,1,2,3,4]
    uint16_t    coordinates_count;
    eap_pointf* coordinates;        // custom coords, or NULL for automatic
    eap_sizeu   resolution;         // screen pixels
    eap_sizef   size;               // physical size in mm
    bool        improve;            // improve existing vs. new calibration
} eap_calibration_config;

typedef struct { eap_message_header header; uint8_t index; eap_pointf point; }  eap_next_calibration_point;
typedef struct { eap_message_header header; uint8_t index; uint8_t progress; }  eap_collecting_calibration_points;

typedef struct {
    uint8_t    index;
    eap_pointf accuracy;   // offset to the calibration point
    float      precision;  // precision radius
    uint8_t    quality;    // 0–255
} eap_quality_point;       // 14 bytes

typedef struct {
    eap_message_header header;
    uint16_t           left_count;
    eap_quality_point* left;    // free with eap_free_finished_calibration()
    uint16_t           right_count;
    eap_quality_point* right;
} eap_finished_calibration;
```

Free dynamic arrays with `eap_free_finished_calibration()` (and
`eap_free_configure_calibration()` if you built a config with heap arrays).

### Video (`eap/video/video_messages.h`)

```c
typedef struct {
    uint16_t       width;
    uint16_t       height;
    uint8_t        channels;
    const uint8_t* pixel_data;         // valid ONLY during the callback — copy to keep
    uint32_t       pixel_data_length;  // width * height * channels
} eap_video_response;
```

### File status (`eap/file/file_messages.h`)

```c
typedef struct {
    eap_message_header   header;
    eap_file_status_code status;      // SUCCESS / PROGRESS / FAILED
    uint16_t             progress;    // 0–100 when PROGRESS
    char                 error_message[256];  // when FAILED
    uint16_t             error_message_length;
} eap_file_status_response;
```

Constants: `EAP_FILE_MAX_CHUNK_DATA` (4048), `EAP_FILE_MAX_CHUNKS`,
`EAP_FILE_MAX_SIZE`.

### Logging (`eap/logging/logging_messages.h`)

```c
typedef struct {
    eap_message_header header;
    eap_log_level      level;
    char               message[512];   // NUL-terminated UTF-8
    uint16_t           message_len;
} eap_logging_response;
```

Helper: `eap_log_level_name(level)`.

---

## Enumerations & return codes

### `eap_result` — return codes

| Value | Meaning |
|-------|---------|
| `EAP_OK` (0) | Success |
| `EAP_ERROR_NOT_FOUND` (−1) | Device/resource not found |
| `EAP_ERROR_TIMEOUT` (−2) | Operation timed out |
| `EAP_ERROR_INVALID_STATE` (−3) | Not valid in the current state (e.g. sending before `LINK_SYNCED`) |
| `EAP_ERROR_COMMUNICATION` (−4) | Transport/I/O error |
| `EAP_ERROR_PARSE` (−5) | Malformed data |
| `EAP_ERROR_MEMORY` (−6) | Allocation failure |

### `eap_connection_state`

`EAP_STATE_DISCONNECTED`, `WAITING_PING`, `HANDSHAKE_SENT`, `WAITING_SYN`,
`SYN_ACK_SENT`, `CONNECTED`, `WAITING_START_EAP_ACK`, `LINK_SYNCED`, `ERROR`.

### `eap_eye_movement_type`

`EAP_EYE_MOVEMENT_FIXATION` (0), `EAP_EYE_MOVEMENT_SACCADE` (1),
`EAP_EYE_MOVEMENT_UNKNOWN` (2).

### `eap_tracking_mode`

`EAP_TRACKING_MODE_BINOCULAR` (0), `EAP_TRACKING_MODE_LEFT` (1),
`EAP_TRACKING_MODE_RIGHT` (2).

### `eap_file_status_code`

`EAP_FILE_STATUS_SUCCESS` (0x0000), `EAP_FILE_STATUS_PROGRESS` (0x0001),
`EAP_FILE_STATUS_FAILED` (0x0002).

### `eap_log_level`

`EAP_LOG_TRACE` (0), `DEBUG` (1), `INFORMATION` (2), `WARNING` (3), `ERROR` (4),
`CRITICAL` (5), `NONE` (6).

### `eap_message_type` (selected)

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

Helpers: `eap_message_type_name(t)`, `eap_message_type_is_request(t)`,
`eap_message_type_is_response(t)`.

---

## Utility helpers

```c
const char* eap_result_to_string(eap_result result);
const char* eap_state_to_string(eap_connection_state state);
const char* skylelib_version(void);   // from <skylelib/skylelib_version.h>
```

---

## Threading model

`eap_client_set_transport()` starts:

- a **background I/O thread** that reads USB, parses iAP2/EAP packets, drives the
  handshake and heartbeat, and invokes your callbacks;
- a **send thread** that drains a dual-tier priority send queue (ACKs/control
  first, bulk file data with anti-starvation).

A dedicated **upload thread** is spawned on demand by
`eap_client_upload_file()`.

You can stop/query the background thread explicitly (mainly for shutdown):

```c
eap_result eap_client_stop_background(eap_client* client);
bool       eap_client_is_background_running(const eap_client* client);
```

> **All callbacks run on the background I/O thread.** Copy any data you need to
> retain (notably `eap_video_response::pixel_data` and
> `eap_logging_response::message`, which are valid only for the duration of the
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
