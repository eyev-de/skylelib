/// Camera frame-rate tier a client asks the device to track at.
///
/// Wire values match `skyle_tracking_power_tier` (one byte, append only) and
/// mirror the firmware's selectable power profiles minus the Saving tier,
/// which the device enters on its own while no eye is trackable.
///
/// Corresponds to the `SetTrackingPowerMode` message (type 0x00E4). An
/// explicit tier overrides the tier the device derives from [HostInfo] until
/// the session ends or [defaultTier] is sent, which is why [SkyleClient]
/// caches and re-sends it on every link-up.
enum TrackingPowerTier {
  /// Hand the choice back to the device's host-derived policy (see [HostInfo]).
  defaultTier(0, null),
  ultraLow(1, 20),

  /// The device default.
  low(2, 30),
  medium(3, 40),
  high(4, 50),
  ultraHigh(5, 60);

  const TrackingPowerTier(this.value, this.fps);

  /// Wire value.
  final int value;

  /// Camera frame rate of the tier; null for [defaultTier] (depends on the host).
  final int? fps;

  static TrackingPowerTier fromValue(int value) =>
      values.firstWhere((e) => e.value == value, orElse: () => TrackingPowerTier.defaultTier);
}
