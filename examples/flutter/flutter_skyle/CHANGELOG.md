## Unreleased

### Added

- Device-initiated calibration aborts reach Dart: the callback struct gains
  `on_calibration_aborted` (appended after `on_host_state`, ABI order shared by
  `native/fanout/flutter_skyle_fanout.h`, the darwin iOS copy and
  `FlutterSkyleCallbacks`), dispatched by the fan-out on Android/macOS/Windows/
  Linux and by the iOS single-slot bridge, and `calibrationStream` emits
  `AbortCalibrationMessage` when the eye tracker sends AbortCalibration
  (0x00C1). Before, skylelib parsed the message but no bridge forwarded it.
  Dart and the native bridge must come from the same release (struct layout).

- Calibration details on `FinishedCalibrationMessage` (needs the skylelib
  release that parses the FinishedCalibration details trailer; older firmware
  keeps working and simply sends no details):
  - `CalibrationResult.details` (`CalibrationDetails?`, null without the
    optional trailer): `success` (decides on its own, a successful fit can
    have every quality at 0), `CalibrationFailureReason` (timeout, point
    timeout, fit rejected, other client calibrating, configuration rejected)
    and `zeroQualityAccuracyDeg`. Accuracy is derived per eye from the quality
    with `accuracyDegForQuality`. A refused calibration start (another client
    calibrates, invalid configuration) arrives as a failed
    `FinishedCalibrationMessage` with that reason.
  - `CalibrationQualityPoint` gains the per-eye `flags` (`isValid`,
    `isExcluded`, `isSynthesised`, `isUnsettled`) and `sampleCount` (both 0
    without details). `isValid` is clear for the untracked eye in a left- or
    right-only mode, whose entry repeats the tracked eye's values;
    `isUnsettled` marks a point the eye tracker collected after its fallback
    wait because the eye was not seen to settle on it (unverified point).
  - `collectCalibrationPoints({int? index})` sends the sequence index of the
    point being confirmed, so newer firmware rejects a stale confirmation;
    without `index` the legacy message is sent.
  - Native ABI: the `skyle_quality_point` mirror gains `flags` and
    `sample_count` in its former padding (still 20 bytes) and the
    `skyle_finished_calibration` mirror gains the appended `has_details`,
    `success`, `reason` and `zero_quality_accuracy_deg`; the bridges keep
    passing the finished calibration by value through `on_calibration_finished`.
    The bridges export `flutter_skyle_collect_calibration_points_at` (looked
    up optionally; Dart falls back to the legacy send against an older shim).

- `SkyleNotReadyException` (a `SkyleException`), thrown by `startCalibration`
  (see Breaking Changes).

- `SkyleClient.stopUsbHost()` now performs the Skyle Link handover on desktop
  too (macOS/Windows/Linux): it disables the transport supervisor - as hub
  owner BYE(handover) to every link client, hub stop, USB release through the
  platform ownership callback (WinUSB/IOKit claim closed) - and waits, bounded
  by the new `timeout` parameter (default 2500 ms), until the supervisor
  reports DISABLED. Previously a no-op outside Android, so a quitting desktop
  hub owner dropped its TCP connections and USB handle with the process and
  clients only recovered through loss detection. Call it first thing in the
  app's quit path; the example app does so from `AppLifecycleListener.
  onExitRequested`.

- Android: the Skyle X host identity is now `de.eyev.skylex` (was `skylex`),
  matching the desktop identity, so hub logs, HELLO app ids and
  restore-on-disconnect keys read the same on every platform.

- skylelib (Windows): a WinUSB open that fails with ERROR_ACCESS_DENIED or
  ERROR_SHARING_VIOLATION on a present device now logs "held by another
  process - will retry" instead of the misleading "install the WinUSB driver"
  hint - that is the normal picture while a Skyle Link peer owns the tracker.

- `SkyleControl.sendHostInfo(HostInfo)` / `hostInfo`: tell the device which
  tablet family the app runs on (`HostDeviceType`: iPad, iPad mini, iPad Air,
  iPad Pro, Android tablet, Windows tablet, unknown) plus the platform model
  id. The device picks its camera power tier from it (iPad Pro tracks at
  60 fps, everything else at 30 fps) and forgets it when the session ends, so
  the value is cached and re-sent on every link-up like display info. Wire:
  new EAP message `SetHostInfo` (0x00E3). Native: bridges export
  `flutter_skyle_send_host_info`; requires a skylelib with
  `skyle_client_send_host_info` (a release newer than 2.1.0).

- `SkyleControl.sendTrackingPowerMode(TrackingPowerTier)` / `trackingPowerTier`:
  ask the device for an explicit camera frame-rate tier (`ultraLow` 20 fps,
  `low` 30 fps, `medium` 40, `high` 50, `ultraHigh` 60; `defaultTier` hands
  the choice back to the host-info policy). Overrides the tier the device
  derives from `sendHostInfo` until the session ends, so the value is cached
  and re-sent on every link-up like host info. Wire: new EAP message
  `SetTrackingPowerMode` (0x00E4, 1 byte). Native: bridges export
  `flutter_skyle_send_tracking_power_mode`; requires a skylelib with
  `skyle_client_send_tracking_power_mode`.

- `SkyleControl.hasReceivedControl`: true once the device has pushed its
  control state in the current link session (resets on link loss), so a late
  subscriber can tell a device-fresh `controlData` from the pre-push default.

- Skyle Link host state read-back (extension message 0xFF0A, HOST_STATE): link
  clients see what the hub-hosting app (Skyle X) actually shows via
  `hostVisibilityStream` / `hostVisibility(id)` /
  `isHostMenuBarVisible` / `isHostPointerVisible` (null = unknown) and the
  generic `hostStateStream` / `hostState(id)`; `hubSupportsHostState` tells an
  unknown that will resolve from one that never will. The hosting app publishes
  its real state with `publishMenuBarVisibility` / `publishPointerVisibility`
  (generic `publishHostState`) - process-wide and mode independent, so it can
  be called at startup before the supervisor has elected an owner.
  `flutter_skyle_riverpod` adds `skyleHostVisibilityProvider(controlId)`
  (seeded, `bool?`). Native: `flutter_skyle_callbacks` gained the appended
  field `on_host_state` (after `on_link_client`; ABI order, Dart and iOS
  mirrors match) and the link glue exports `flutter_skyle_link_get_host_state`,
  `flutter_skyle_link_get_host_visibility`,
  `flutter_skyle_link_publish_host_state`,
  `flutter_skyle_link_get_hub_capabilities`. Requires skylelib with HOST_STATE
  support (Skyle Link protocol 1.2); against an older library the new symbols
  resolve to null and visibility stays unknown.

- Skyle Link host control (extension message 0xFF09): a local-link client
  commands the hub-hosting app (Skyle X) via `sendHostControl` and the typed
  helpers `setHostMenuBarVisible` / `setHostPointerVisible` /
  `startHostCalibration` (fire-and-forget; refused with `false` when this
  process is the hub owner or not in local-link mode). The hub owner receives
  the commands on `hostControlStream` and hub client presence
  (connect/disconnect with the sender app id, the key for its
  restore-on-disconnect policy) on `linkClientStream`;
  `flutter_skyle_riverpod` adds the matching `skyleHostControl` and
  `skyleLinkClients` providers (unseeded - commands/events, not state).
  Native: `flutter_skyle_callbacks` gained the appended fields
  `on_host_control` then `on_link_client` (this order is ABI; the Dart and
  iOS mirrors match), and the link glue exports
  `flutter_skyle_link_send_host_control`. Requires a skylelib rebuilt with
  HOST_CONTROL support; against an older native library only the new symbols
  resolve to null and the send APIs report unavailable.

### Breaking Changes

- `startCalibration` throws `SkyleNotReadyException` when the link is not
  ready instead of returning silently, so the app can tell the user that no
  calibration was started. Callers without a try/catch now get an unhandled
  exception where nothing happened before.
- `SkyleCalibration.collectCalibrationPoints` gained an optional named
  parameter (`{int? index}`). Call sites compile unchanged, but classes that
  implement `SkyleCalibration` or `SkyleClient` (fakes, mocks) must add the
  parameter to their overrides.
- Calibration results from eye trackers with the 2026-10 calibration rework:
  `CalibrationQualityPoint.quality` is computed from the held-out accuracy
  (older firmware sent a constant 200 for every point with data), so a
  `quality > 128` check can now reject points it used to accept, and
  `precision` is the RMS scatter in display px instead of the mean offset
  length. A failed calibration now ends with a `FinishedCalibrationMessage`
  whose points all have quality 0, where older firmware sent nothing.
- Riverpod providers moved to the new sibling package `flutter_skyle_riverpod`.
  Replace `import 'package:flutter_skyle/flutter_skyle_providers.dart';` with
  `import 'package:flutter_skyle_riverpod/flutter_skyle_riverpod.dart';` (it
  re-exports the full flutter_skyle API). flutter_skyle itself no longer depends
  on Riverpod - its API is plain Dart streams.
- Dropped unused dependencies: `collection`, `plugin_platform_interface`,
  `riverpod`, `riverpod_annotation` (and the codegen dev dependencies).

### Changed

- Both Apple platforms now build as Swift Packages, dual with CocoaPods:
  `macos/flutter_skyle/Package.swift` and `ios/flutter_skyle/Package.swift`, with
  the sources moved to `<platform>/flutter_skyle/Sources/` (Swift target
  `flutter_skyle` + C target `flutter_skyle_bridge`, since SPM allows no mixed
  target). The podspecs compile the SAME files and keep working for CocoaPods
  consumers; the prebuilt `skylelib.xcframework` is a `binaryTarget` resolved
  from `<platform>/flutter_skyle/.skylelib/` (created by `pod install` or by
  `scripts/vendor_xcframework.sh`) or from the checksum-pinned GitHub release.
  Apps that enable Swift Package Manager in the Flutter tool need no Podfile on
  macOS or iOS any more.
- iOS minimum deployment target lowered from 14.0 to 13.0 - the floor of the
  prebuilt iOS slices and of Flutter itself. A higher package minimum than the
  consuming app's target fails SPM resolution outright.
- The multi-engine callback fan-out (previously Android-only) is now the
  mechanism on ALL pull-mode platforms (Android, macOS, Windows, Linux):
  every Flutter engine in a process registers its own subscriber and receives
  all callbacks independently (shared module `native/fanout/`). Desktop
  engines register with an engine token (`flutter_skyle_add_callbacks_engine`);
  a re-add with the same token after a hot restart reaps the stale subscriber
  natively. The short-lived desktop primary/passive engine guard
  (`flutter_skyle_try_acquire_primary` / `flutter_skyle_release_primary`) and the
  process-wide Dart suspension slot
  (`flutter_skyle_set_suspend_state_callback`) are removed - suspension events
  now reach every engine through its subscriber's `on_suspend_state`. iOS
  stays single-slot push mode.

### Fixed

- Skyle Link hub: file transfers from hub clients lost chunks. Forwarded
  StartFile/FileData/EndFile frames went through the 32-slot priority send
  ring, which dropped 4 KB chunks whenever the USB writer stalled for a few
  hundred ms, and the device then failed the upload at its chunk-count check
  ("received 1591 of 2754 chunks"). They now use the bulk FIFO with
  backpressure, like an own `uploadFile`.
- Skyle Link hub: the final StatusFile (SUCCESS / FAILED) never reached the
  uploading hub client - the hub released the transfer on the client's EndFile,
  but the device only answers after it. The transfer is now released by the
  final status.
- Android: the USB layer (`UsbEndpointManager`, `SkyleUsbHost`,
  `FlutterSkylePlugin`) logs through `android.util.Log`. `io.flutter.Log.d` is
  compiled out of release builds, so field logs showed no attach, permission,
  open or ownership events at all.

- Android: a tracker plugged in while the app was running could stay
  unconnected until the app was restarted. When the system's "Allow access"
  dialog was not confirmed within 5 s, the plugin fell back to its own
  permission request and stopped watching; a grant from the system dialog after
  that, or a dismissed duplicate dialog (reported as denied), left the permitted
  device closed. The permission is now watched for as long as the device stays
  attached, a "denied" response is checked against `hasPermission()`, failed
  opens are retried without a limit while the device is attached, and every
  engine attach (`SkyleUsbHost.start` when already running) re-enters the open
  path for an attached tracker that is not open.

- skylelib: a FinishedCalibration (0x00C6) that the message buffer dropped
  (buffer full), cleared or still held at destroy leaked its quality point
  arrays; the buffer now frees them, while a dequeued message stays owned by
  the dispatcher as before. A FinishedCalibration the buffer refuses is freed
  right away.

- skylelib: `skyle_client_start_calibration` rejects a configuration whose
  ConfigureCalibration payload would not fit its 512-byte buffer (or that has
  a non-zero count with a NULL array) with `SKYLE_ERROR_MEMORY` instead of
  writing past the stack buffer.

- Docs: CollectingCalibrationPoints (0x00C4) progress is 0-255 on the wire
  (255 = point complete), not a 0-100 percentage
  (`calibration_messages.h`, `SKYLE_MESSAGES.md`, `SKYLE_CLIENT_API.md`,
  `CalibrationProgress`); the CLI example now prints it as a percentage.

- File uploads (`uploadFile`, the firmware update path) failed with
  `Hash mismatch` most of the time: skylelib queued StartFile on the priority
  ring but the FileData chunks on the bulk ring, and the send thread's
  anti-starvation rule let chunk 0 overtake StartFile, so the device dropped it
  as belonging to an unknown transfer. StartFile now goes through the bulk ring
  with the chunks and EndFile (4 of 5 bench uploads failed before, 0 of 6
  after). Without a hash the same race used to produce a silently truncated
  file; firmware from October 2026 on rejects such uploads with
  `Missing chunks: received X of Y`.

- Android: unplugging the tracker no longer tears the Skyle Link hub down.
  `UsbEndpointManager` pushed `usb_capable=false` on every USB_DEVICE_DETACHED
  broadcast, which the supervisor treats as a permission revocation: as hub
  owner it ran the live handover (BYE(handover) to every link client, port
  freed) and then dialed a hub that could not exist until the tracker was back,
  so every unplug cost the hub plus a re-election and every client a re-dial.
  `usb_capable` is now sticky as the spec intends - seeded true in
  `SkyleUsbHost.start` unless a tracker is attached without permission, cleared
  only by an explicit permission denial - so ownership and the hub survive the
  unplug (clients keep their connection and see STATE disconnected) and the
  attach -> manifest grant -> open path brings the link back without an
  election. A host app without a tracker attached now binds the hub at
  start-up instead of waiting for the first attach.

- skylelib client (all pull-mode platforms): four handshake dead ends that
  previously needed a cable replug. (1) A firmware soft reset while the link
  was synced (its 2 s heartbeat watchdog, e.g. after the app process was frozen
  or the host suspended) left the client LINK_SYNCED forever: the firmware's
  1 Hz iAP2 probe marker refreshed the RX-staleness timer while every heartbeat
  was dropped. The marker now restarts the handshake and is answered in place.
  (2) A SYN received in WAITING_PING (firmware already past probing because an
  earlier client instance answered the marker) is answered instead of being
  ignored until the connect timeout. (3) A process that never synced now sends
  RST after a handshake timeout, the only thing a firmware stuck after its SYN
  loop reacts to. (4) Several link packets in one USB transfer (the firmware
  sends no ZLP after a 512-byte multiple) are all parsed instead of only the
  first; occurrences are counted and logged.
- iOS: `BoundedQueue.swift` and `OutputStreamManager.swift` were missing
  `import Foundation` and could not compile (both use `DispatchQueue` /
  `DispatchSemaphore` / `Data`).
- Android: the USB ownership grant now restarts the EAP client's background
  threads (the supervisor stops them on every release; the Kotlin listener
  only re-opens the USB device). Without this, any ownership cycle after the
  initial bring-up (USB unplug/replug, a Skyle Link handover) opened the
  device but never read from it - the tracker's 2.5 s heartbeat timeout then
  soft-reset it in an endless USB detach/re-enumerate loop.
- Android: `SkyleUsbHost` no longer claims the reserved skylex/tier-0 Skyle
  Link identity for every host-owning consumer app. Only the Skyle X package
  (`de.eyev.skylex`) gets tier 0; every other app resolves its identity from
  the `de.eyev.flutter_skyle.APP_ID` / `PRIORITY_TIER` manifest meta-data
  (default: packageName, tier 2 - same keys as the pure-client path).

## 0.0.1 - November 2, 2025

### Initial Release

High-performance Flutter plugin for Skyle eye-tracking device communication.

#### Features
- ✅ Native C library integration via FFI
- ✅ Direct JNI callbacks for Android USB I/O
- ✅ Real-time gaze streaming (60Hz)
- ✅ Positioning data with iris tracking (30Hz)
- ✅ Interactive calibration (5/9-point)
- ✅ Complete iAP2/EAP protocol implementation
- ✅ Riverpod providers for reactive state management
- ✅ Comprehensive data models (gaze, positioning, calibration)
- ✅ Connection state management with automatic handshake
- ✅ Error handling and recovery

#### Platform Support
- **Android**: USB Host API (minSdk 24)
- **iOS**: Planned (External Accessory Framework)

#### Architecture
- Zero-copy data flow
- Single background thread for protocol handling
- Symmetric read/write via direct callbacks
- Type-safe FFI bindings
- Immutable data models

#### Performance
- <5ms latency (USB → Dart)
- <1% CPU usage
- ~10MB memory footprint

#### Documentation
- Complete API documentation
- Architecture guide
- Quick start examples
- Protocol specifications
- Native library reference

#### Known Limitations
- Android only (iOS in development)
- Single device support
- Requires USB Host capability

---

### Development History

#### Phase 1: Build System (Completed)
- Git submodule integration
- CMake build configuration
- NDK/Gradle setup
- FFI dependencies

#### Phase 2: C Bridge Layer (Completed)
- JNI transport callbacks
- Struct adapters (10 callbacks)
- Memory management
- Error handling

#### Phase 3: Dart FFI (Completed)
- Native bindings (380 lines)
- FFI wrapper (470 lines)
- High-level API (250 lines)
- Stream controllers

#### Phase 4: Data Models (Completed)
- GazeData (complex gaze with movement types)
- PositioningData (face, eyes, iris)
- CalibrationConfig/Point/Progress/Result
- ConnectionState enum
- ControlData

#### Phase 5: Platform Integration (Completed)
- FlutterSkylePlugin (Kotlin)
- UsbEndpointManager (direct callbacks)
- Method channels for USB control
- JNI bridge layer

#### Phase 6: Riverpod (Completed)
- Optional provider integration
- 10 stream providers
- Auto-dispose client management
- Reactive UI patterns

#### Phase 7: Example App (Completed)
- Connection management UI
- Gaze visualization
- Positioning/iris display
- State monitoring
- Error handling

---

### Migration Notes

This is the first public release. No migration needed.

### Breaking Changes

N/A - Initial release

### Bug Fixes

N/A - Initial release

### Performance Improvements

Compared to pure Dart implementation:
- 10x reduction in latency (50ms → 5ms)
- 90% reduction in CPU usage
- 80% reduction in memory usage
- Native parsing vs Dart byte manipulation

---

**Contributors**: eyeV GmbH Development Team
