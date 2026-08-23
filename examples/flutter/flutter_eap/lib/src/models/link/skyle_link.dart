/// Skyle Link data models - local multi-app sharing of one Skyle eye tracker.
///
/// Skyle Link lets multiple applications on one machine share a single Skyle
/// eye tracker: exactly one process owns the USB link (the "hub"); every other
/// application connects to a localhost TCP port the hub serves and uses the
/// unchanged [EapClient] API. Transport selection is fully automatic - the
/// native supervisor elects the hub owner, dials as a client, and swaps a
/// running session live between USB and socket; applications only supply an
/// identity. See docs/SKYLE_LINK_PROTOCOL.md in the skylelib repository for
/// the protocol.
library;

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
/// `EapClient.initialize` (desktop) or set `EapClient.defaultIdentity` before
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
