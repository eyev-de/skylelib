# Transport Architecture

This document describes how raw USB data flows between the Skyle eye-tracker and the
Dart/Flutter layer on every supported platform, covering connection setup, the
sending and receiving paths, threading models, and hot-restart behaviour.

## High-Level Overview

```
Flutter/Dart
  EapClientFfi  (lib/src/ffi/eap_client_ffi.dart)
    |  FFI (NativeCallable.listener for callbacks, direct calls for commands)
    v
C Bridge Layer  (platform-specific)
    |  Adapter callbacks: C struct -> Dart via NativeCallable
    v
C Library  (native/skylelib/)
    eap_client  -- protocol parsing, state machine, heartbeat
    iap_protocol -- iAP2 framing, checksums, SYN/ACK handshake
    |
    v  transport_read / transport_write  (function pointers)
Platform USB Layer
    iOS:     ExternalAccessory (EASession streams)
    Android: USB Host API (bulkTransfer via JNI)
    macOS:   IOKit (IOUSBInterfaceInterface)
    Windows: WinUSB (native, via rawbulk_winusb.c)
    |
    v
Skyle Eye-Tracker  (VID=0x3729, PID=0x7333)
```

Two callback chains exist on every platform:

1. **Transport callbacks** -- raw USB read/write, provided by the platform layer
   to the C library via function pointers.
2. **Message callbacks** -- parsed EAP messages, provided by Dart to the C bridge
   via `flutter_eap_set_callbacks()`.

## Shared Dart FFI Layer

All platforms share the same Dart code in `lib/src/ffi/eap_client_ffi.dart`.

### Initialisation

1. Check `flutter_eap_is_initialized()` to detect hot restart vs fresh start.
2. Create `NativeCallable<T>.listener()` for every message type (gaze,
   positioning, version, control, calibration, video, file status, state, error).
   These are thread-safe: the C background thread can invoke them and Dart
   receives the call on its isolate.
3. Allocate a `FlutterEapCallbacks` struct, fill it with the native function
   pointers from step 2, and call `flutter_eap_set_callbacks()`.
4. Call `_configureTransport()` via `MethodChannel('flutter_eap/usb')` --
   this triggers the platform plugin to set up USB I/O.

### Sending a command (e.g. `enableGaze()`)

```
Dart: _bindings!.enableGaze(_clientPtr!, true)
  -> FFI call to C bridge: flutter_eap_enable_gaze()
  -> C library: eap_client_enable_gaze()
  -> Enqueues EAP message on send queue
  -> Send thread calls transport_write() -> USB
```

### Receiving a message (e.g. gaze data)

```
USB -> transport_read() (or process_data on iOS)
  -> C library parses iAP2 + EAP
  -> C adapter (on_gaze_adapter) locks mutex, invokes Dart callback
  -> NativeCallable.listener posts to Dart isolate
  -> _onGazeCallback() adds GazesData to _gazeController stream
  -> App UI rebuilds
```

### Library loading

| Platform | Method |
|----------|--------|
| Android  | `DynamicLibrary.open('libflutter_eap.so')` |
| iOS      | `DynamicLibrary.process()` (symbols linked into app) |
| macOS    | `DynamicLibrary.process()` (symbols linked into app) |

### Destruction

Order is critical to prevent "callback invoked after deleted" crashes:

1. `clearCallbacks()` -- mutex-protected, stops C from calling Dart
2. `destroy()` -- stops background thread, waits for it, frees C client
3. Close all `NativeCallable` listeners
4. Close all `StreamController`s

---

## iOS (ExternalAccessory, Push Mode)

iOS uses Apple's **ExternalAccessory** framework which provides stream-based I/O
via `EASession`. There is **no background read thread** in the C library. Swift
pushes received bytes into the C parser.

### Key difference: iAP2 is handled by iOS

On other platforms the C library performs the full iAP2 handshake. On iOS,
`EASession` handles the iAP2 link layer transparently. The C library only sees
application-layer EAP data, and the connection state jumps straight to
`LINK_SYNCED` on session open.

### Files

| File | Role |
|------|------|
| `ios/Classes/FlutterEapPlugin.swift` | Plugin entry point, EAAccessory management, StreamDelegate |
| `ios/Classes/OutputStreamManager.swift` | Async output stream writer with backpressure |
| `ios/Classes/BoundedQueue.swift` | Thread-safe bounded FIFO queue |
| `darwin/Classes/flutter_eap_bridge_apple.c` | C bridge (shared with macOS), push-mode functions |

### Connection Setup

1. `FlutterEapPlugin.register()` registers for `EAAccessoryDidConnect` /
   `EAAccessoryDidDisconnect` notifications and sets up a MethodChannel.
2. Dart calls `configureTransport` via MethodChannel.
3. `configureTransport()` gets the singleton C client and calls
   `flutter_eap_configure_push_transport()` with two Swift callbacks:
   - `transportWrite` -- called by C when it needs to send data
   - `deviceCheck` -- called by C to check if the accessory is connected
4. Attempts to find and connect to an already-present accessory.

### Receiving Data

```
Skyle Device
  -> iOS iAP2 link layer (handled by OS)
  -> EASession.inputStream
  -> StreamDelegate: .hasBytesAvailable fires
  -> readAndProcessData() reads up to 4096 bytes in a loop
  -> flutter_eap_process_data(ptr, buffer, bytesRead)
  -> eap_client_process_received_data() in C library
  -> C parses EAP message, invokes adapter callback
  -> Adapter locks mutex, calls Dart NativeCallable
  -> Dart stream emits parsed model
```

### Sending Data

```
Dart: enableGaze(true)
  -> FFI -> C library builds EAP packet
  -> C calls transportWrite callback
  -> Swift wraps bytes in Data, calls writer.enqueueData(bytes)
  -> OutputStreamManager:
     - Enqueues Data into BoundedQueue (max 10,000 items)
     - writeQueue (DispatchQueue) drains the queue
     - Waits on spaceAvailableSemaphore
     - Writes to EASession.outputStream in a loop until all bytes sent
  -> iOS iAP2 link layer -> USB -> Device
```

### Threading Model

- **No C background thread.** Push mode means C only runs when Swift feeds data.
- Input stream callbacks run on the **main RunLoop**.
- Output writes happen on a dedicated **DispatchQueue** (`de.eyev.writequeue`).
- A periodic `flutter_eap_tick()` call (Swift timer, ~200ms) handles heartbeat
  and timeout detection.

### Session Lifecycle

- **Open:** `EASession(accessory:forProtocol:"de.eyev.eap")` -- opens streams,
  calls `flutter_eap_connect()` which sets state to LINK_SYNCED.
- **Close:** `closeSession()` calls `flutter_eap_disconnect()`, closes streams.
- **Reconnect:** On `EAAccessoryDidConnect` notification, a new session is
  opened automatically.

---

## Android (USB Host API, Pull Mode via JNI)

Android uses the **USB Host API** (`android.hardware.usb`) with a **pull-based**
model: a C background thread calls Kotlin's `read()`/`write()` methods via JNI.

### Files

| File | Role |
|------|------|
| `android/.../FlutterEapPlugin.kt` | Plugin entry, USB init, multi-engine support |
| `android/.../UsbEndpointManager.kt` | USB Host API: permissions, device open, bulk transfers |
| `android/.../EapClientJni.kt` | JNI function declarations |
| `android/src/main/cpp/flutter_eap_bridge.c` | JNI transport callbacks + Dart adapters |
| `android/src/main/cpp/jni_bridge.c` | JNI entry points |

### Connection Setup

1. `FlutterEapPlugin.onAttachedToEngine()` initialises USB once (first engine).
   Creates `UsbEndpointManager` and registers a BroadcastReceiver for USB intents.
2. Dart calls `configureTransport` via MethodChannel.
3. Kotlin creates the C client via JNI, registers USB transport callbacks.
4. C stores JNI references, sets `transport_read`/`transport_write`/`usb_device_check`
   function pointers, and starts the background I/O thread.

### Receiving Data

```
Skyle Device
  -> USB IN bulk endpoint
  -> C background thread calls transport_read()
  -> JNI: CallIntMethod(kotlin_callback, read_method, jbuffer, timeout)
  -> UsbEndpointManager.read(): conn.bulkTransfer(epIn, buffer, size, timeout)
  -> Bytes returned via JNI -> C receives bytes
  -> C library parses iAP2 framing + EAP message
  -> Adapter callback -> Dart NativeCallable -> Stream
```

The read buffer (8192 bytes) is pre-allocated as a JNI global reference and reused,
eliminating ~1.6 MB/sec of GC pressure.

### Sending Data

```
Dart: enableGaze(true)
  -> FFI -> C library enqueues message on send queue
  -> Send thread dequeues, calls transport_write()
  -> JNI: creates jbyteArray from C data, calls Kotlin write()
  -> UsbEndpointManager.write(): conn.bulkTransfer(epOut, data, size, 100ms)
  -> USB -> Device
```

### Threading Model

- **C background I/O thread** -- polls `transport_read()` continuously.
- **C send thread** -- drains a dual-tier send queue (ACK priority + bulk).
- **No Kotlin threads** -- methods are called synchronously from C via JNI.
- JNI thread attachment is cached per-thread with `pthread_key_t`.

### USB Device Discovery

- `UsbEndpointManager` listens for USB attach/detach intents via BroadcastReceiver.
- Requests user permission via system dialog when target device detected.
- Claims interface 1 (iAP bulk endpoints), finds IN and OUT bulk endpoints.

### Full iAP2 Handshake

Unlike iOS, Android handles the complete 9-state iAP2 handshake in the C library
because there is no OS-level ExternalAccessory equivalent.

---

## macOS (IOKit, Pull Mode)

macOS uses **IOKit** for direct USB access via bulk endpoints. Like Android, it
uses a pull-based model with a C background thread, but all USB I/O is pure C.

### Files

| File | Role |
|------|------|
| `macos/Classes/FlutterEapPlugin.swift` | Plugin entry, triggers IOKit transport config |
| `darwin/Classes/flutter_eap_bridge_apple.c` | C bridge (shared with iOS) |
| `native/skylelib/src/eap_transport_iokit.c` | IOKit USB transport: device discovery, read, write |

### Connection Setup

1. Dart calls `configureTransport` via MethodChannel.
2. Swift calls `flutter_eap_configure_iokit_transport(ptr, 0x3729, 0x7333)`.
3. C creates an `eap_transport_iokit` struct, finds the USB device via IOKit
   registry, opens it, claims interface 1, discovers bulk IN/OUT pipes.
4. Sets transport function pointers and starts the background I/O thread.

### Threading Model

- **C background I/O thread** -- blocks on `ReadPipeTO()` (1000ms timeout).
- **C send thread** -- drains send queue, calls `WritePipe()`.
- **No Swift USB code** -- all I/O is pure C via IOKit.

### IOKit Device Discovery

- `iokit_find_service()` creates a matching dictionary and uses
  `IOServiceGetMatchingServices()` to find the device by VID/PID.
- Tries `IOUSBHostDevice` (macOS 10.15+) first, falls back to `IOUSBDevice`.
- Iterates interfaces, prefers interface 1, finds bulk IN/OUT pipes.

### Device Check and Reconnection

- If connected, trusts cached state (avoids expensive IOKit registry scans).
- If disconnected, probes registry for device presence.
- On device reappearance, attempts `iokit_open_device()` to reconnect.

---

## Windows (WinUSB, Pull Mode)

Uses native WinUSB API for USB bulk transfers -- native USB API.

### Files

| File | Role |
|------|------|
| `windows/flutter_eap_plugin.cpp` | Plugin entry, triggers WinUSB transport config |
| `windows/flutter_eap_bridge_windows.c` | C bridge (Windows-specific) |
| `native/skylelib/src/rawbulk_winusb.c` | WinUSB USB transport: device discovery via SetupDi, read, write |
| `native/skylelib/src/eap_transport_usb.c` | Transport wrapper around rawbulk (read/write/check callbacks) |

### Connection Setup

1. Dart calls `configureTransport` via MethodChannel.
2. C++ plugin calls `flutter_eap_configure_usb_transport(client, 0x3729, 0x7333)`.
3. C creates an `eap_transport_usb` struct which calls `rawbulk_open()`.
   `rawbulk_winusb.c` discovers the device via SetupDi (device interface path or
   PDO name fallback), opens it with WinUSB, discovers bulk IN/OUT endpoints.
4. Sets transport function pointers and starts the background I/O thread.

### Threading Model

- **C background I/O thread** -- blocks on `WinUsb_ReadPipe()` with timeout.
- **C send thread** -- drains send queue, calls `WinUsb_WritePipe()`.

---

## Platform Comparison

| Aspect | iOS | Android | macOS | Windows |
|--------|-----|---------|-------|---------|
| **USB API** | ExternalAccessory | USB Host API | IOKit | WinUSB |
| **I/O Model** | Push | Pull | Pull | Pull |
| **Background read thread** | No | Yes (C) | Yes (C) | Yes (C) |
| **iAP2 handshake** | OS handles it | C library | C library | C library |
| **State on connect** | -> LINK_SYNCED | -> WAITING_PING -> ... | -> WAITING_PING -> ... | -> WAITING_PING -> ... |
| **Bridge code** | darwin/flutter_eap_bridge_apple.c | android/cpp/flutter_eap_bridge.c | darwin/flutter_eap_bridge_apple.c | windows/flutter_eap_bridge_windows.c |
| **Plugin language** | Swift | Kotlin | Swift | C++ |

---

## Connection State Machine

All platforms use the same 9-state machine in the C library. iOS is the exception:
because EASession handles iAP2, the state jumps directly to LINK_SYNCED.

```
DISCONNECTED
  |  [Device detected]
  v
WAITING_PING          (send RST, wait for ACK)
  |
  v
HANDSHAKE_SENT        (send detection bytes)
  |
  v
WAITING_SYN           (wait for device SYN)
  |
  v
SYN_ACK_SENT          (send SYN-ACK)
  |
  v
CONNECTED             (iAP2 link up, start EAP session)
  |
  v
WAITING_START_EAP_ACK (wait for EAP session ACK)
  |
  v
LINK_SYNCED           [Ready for application messages]
  |  Heartbeat: version request every 500ms
  |  Timeout: no RX for 2500ms -> reconnect
  v
ERROR -> DISCONNECTED -> [auto-reconnect]
```

### Timeouts

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Heartbeat interval | 500 ms | Version request frequency |
| Heartbeat timeout | 2,500 ms | No RX triggers reconnect |
| RST min interval | 5,000 ms | Prevents reconnect storms |

---

## Hot Restart Handling

Flutter hot restart restarts the Dart VM but native code (C client, USB
connection, background threads) survives. All platforms handle this identically:

1. `EapClientFfi.create()` is called again after restart.
2. `flutter_eap_is_initialized()` returns `true` (bridge context exists).
3. `clearCallbacks()` zeroes stale Dart callback pointers (mutex-protected).
4. New `NativeCallable` listeners are created.
5. `setCallbacks()` installs the new Dart callbacks.
6. `_configureTransport()` is **skipped** -- USB connection is still running.

Result: USB connection preserved, callbacks swapped, no reconnection delay.

---

## Key Files Reference

### Dart (shared, all platforms)

| File | Purpose |
|------|---------|
| `lib/src/ffi/eap_client_ffi.dart` | FFI wrapper, NativeCallable listeners, StreamControllers |
| `lib/src/ffi/eap_client_bindings.dart` | Generated FFI bindings to C functions |
| `lib/src/ffi/ffi_structs.dart` | Dart FFI struct definitions |
| `lib/src/eap_client.dart` | High-level Dart API |
| `lib/src/providers/eap_providers.dart` | Riverpod providers |

### iOS

| File | Purpose |
|------|---------|
| `ios/Classes/FlutterEapPlugin.swift` | EAAccessory management, StreamDelegate, push transport |
| `ios/Classes/OutputStreamManager.swift` | Backpressured async output stream writer |

### Android

| File | Purpose |
|------|---------|
| `android/.../FlutterEapPlugin.kt` | Plugin entry, USB init, multi-engine support |
| `android/.../UsbEndpointManager.kt` | USB Host API: permissions, device open, bulk transfers |
| `android/src/main/cpp/flutter_eap_bridge.c` | JNI transport callbacks + Dart adapters |

### macOS

| File | Purpose |
|------|---------|
| `macos/Classes/FlutterEapPlugin.swift` | Plugin entry, triggers IOKit transport config |

### Shared Apple (iOS + macOS)

| File | Purpose |
|------|---------|
| `darwin/Classes/flutter_eap_bridge_apple.c` | C bridge: callback adapters, transport setup |

### Windows

| File | Purpose |
|------|---------|
| `windows/flutter_eap_plugin.cpp` | Plugin entry, triggers WinUSB transport config |
| `windows/flutter_eap_bridge_windows.c` | C bridge: callback adapters, transport setup |

### Native C Library

| File | Purpose |
|------|---------|
| `native/skylelib/src/eap_client.c` | Core: state machine, background thread, message dispatch |
| `native/skylelib/src/iap_protocol.c` | iAP2 packet parsing and building |
| `native/skylelib/src/rawbulk_winusb.c` | WinUSB bulk transfer layer (Windows) |
| `native/skylelib/src/eap_transport_usb.c` | Transport wrapper around rawbulk (Windows) |
| `native/skylelib/src/eap_transport_iokit.c` | IOKit USB transport (macOS) |
