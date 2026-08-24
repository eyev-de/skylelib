/// Skyle Link data models - local multi-app sharing of one Skyle eye tracker.
///
/// Skyle Link lets multiple applications on one machine share a single Skyle
/// eye tracker: exactly one process owns the USB link (the "hub"); every other
/// application connects to a localhost TCP port the hub serves and uses the
/// unchanged [SkyleClient] API. Transport selection is fully automatic - the
/// native supervisor elects the hub owner, dials as a client, and swaps a
/// running session live between USB and socket; applications only supply an
/// identity. See docs/SKYLE_LINK_PROTOCOL.md in the skylelib repository for
/// the protocol.
library;

import 'dart:typed_data';

/// Default Skyle Link TCP port (SKYLE_LINK_DEFAULT_PORT).
const int skyleLinkDefaultPort = 35729;

/// Skyle Link priority tiers (skyle_link_tier). Lower value = higher priority.
abstract final class SkyleLinkTier {
  /// The Skyle X app/service itself.
  static const int skylex = 0;

  /// Partner applications.
  static const int partner = 1;

  /// Everything else.
  static const int defaultTier = 2;
}

/// Skyle Link identity of this application - sent in HELLO and used by the
/// automatic transport supervisor for hub elections and preemption. Pass to
/// `SkyleClient.initialize` (desktop) or set `SkyleClient.defaultIdentity` before
/// the first initialize. On Android the platform layer owns the identity
/// (manifest meta-data / the skylex service); a Dart identity is ignored there.
class SkyleLinkIdentity {
  const SkyleLinkIdentity({required this.appId, this.priorityTier = SkyleLinkTier.defaultTier});

  /// Application identifier sent in HELLO (max 128 UTF-8 bytes). Also shown
  /// as the suspension holder to other clients.
  final String appId;

  /// skyle_link_tier value; lower = higher priority (see [SkyleLinkTier]).
  final int priorityTier;
}

/// Eye-control suspension state shared across all Skyle Link participants.
///
/// While suspended, the hub-hosting app (Skyle X) hides its gaze UI and stops
/// synthesizing input from gaze; [holderAppId] names the client holding the
/// lease. The lease dies with the holder's connection.
class SkyleLinkSuspendState {
  const SkyleLinkSuspendState({required this.suspended, this.holderAppId});

  /// True while eye control is suspended.
  final bool suspended;

  /// App id of the suspension lease holder; null when not suspended.
  final String? holderAppId;

  @override
  bool operator ==(Object other) =>
      other is SkyleLinkSuspendState && other.suspended == suspended && other.holderAppId == holderAppId;

  @override
  int get hashCode => Object.hash(suspended, holderAppId);

  @override
  String toString() => 'SkyleLinkSuspendState(suspended: $suspended, holderAppId: $holderAppId)';
}

/// Skyle Link host-control ids (skyle_link_host_control). Well-known values
/// for [SkyleLinkHostControl.controlId]; unknown codes flow through as raw
/// ints - receivers ignore what they do not know, so new ids need no plugin
/// change.
abstract final class SkyleLinkHostControlId {
  /// u8 visible (0/1). 0 hides the menu bar completely; the pause edge
  /// feature is disabled with it.
  static const int menuBar = 1;

  /// u8 visible (0/1). 0 hides the pointer overlay; snap-to-item and the
  /// left/right edges are disabled with it.
  static const int pointerOverlay = 2;

  /// Optional u8 point count (absent/0 = app default, else 5 or 9). Brings
  /// the hub-hosting app to the foreground and starts a calibration.
  static const int startCalibration = 3;
}

/// A fire-and-forget HOST_CONTROL command received by the hub this process
/// serves. Only the hub owner receives these; a local-link client sends them
/// via `SkyleClient.sendHostControl`. Commands, not state: nothing is cached
/// and the last writer wins at the receiver.
class SkyleLinkHostControl {
  const SkyleLinkHostControl({required this.controlId, required this.value, this.senderAppId});

  /// Which control ([SkyleLinkHostControlId]; unknown ids pass through).
  final int controlId;

  /// Raw value bytes (layout per control id, append-only; may be empty).
  final Uint8List value;

  /// App id of the sending client; null when unknown.
  final String? senderAppId;

  @override
  String toString() => 'SkyleLinkHostControl(controlId: $controlId, value: $value, senderAppId: $senderAppId)';
}

/// A client connected to or disconnected from the hub this process serves.
/// Only the hub owner receives these - the disconnect events carry the
/// [appId] a receiver-side restore-on-disconnect policy keys on.
class SkyleLinkClientEvent {
  const SkyleLinkClientEvent({required this.connected, required this.appId, required this.clientCount});

  /// True when the client connected, false when it disconnected (orderly BYE
  /// and dropped socket alike).
  final bool connected;

  /// App id the client sent in HELLO (not uniqueness-enforced by the hub).
  final String appId;

  /// Number of connected clients after the change.
  final int clientCount;

  @override
  String toString() => 'SkyleLinkClientEvent(connected: $connected, appId: $appId, clientCount: $clientCount)';
}
