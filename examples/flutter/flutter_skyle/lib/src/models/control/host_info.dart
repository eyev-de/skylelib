/// Host device family the app runs on, as the device understands it.
///
/// Wire values match `skyle_host_device_type` (one byte, append only). The
/// device picks its camera power tier from this: [iPadPro] tracks at 60 fps,
/// every other value, including [unknown], at 30 fps.
enum HostDeviceType {
  unknown(0),

  /// Base-model iPad, or an iPad whose family could not be classified.
  iPad(1),
  iPadMini(2),
  iPadAir(3),
  iPadPro(4),
  androidTablet(5),
  windowsTablet(6);

  const HostDeviceType(this.value);

  /// Wire value.
  final int value;

  static HostDeviceType fromValue(int value) =>
      values.firstWhere((e) => e.value == value, orElse: () => HostDeviceType.unknown);
}

/// Description of the host the app runs on, sent to the device so it can pick
/// its camera power tier. The device forgets it when the session ends, which
/// is why [SkyleClient] caches and re-sends it on every link-up.
///
/// Corresponds to the `SetHostInfo` message (type 0x00E3).
final class HostInfo {
  /// Longest model string the wire format keeps, in UTF-8 bytes.
  static const int maxModelBytes = 63;

  final HostDeviceType deviceType;

  /// Platform model identifier, e.g. "iPad14,3" or "SM-X900". May be empty;
  /// it is informational (device log) and does not influence the tier.
  final String model;

  const HostInfo({required this.deviceType, this.model = ''});

  @override
  String toString() => 'HostInfo(${deviceType.name}, \'$model\')';

  Map<String, dynamic> toJson() => {
        'deviceType': deviceType.value,
        'model': model,
      };

  factory HostInfo.fromJson(Map<String, dynamic> json) => HostInfo(
        deviceType: HostDeviceType.fromValue(json['deviceType'] as int),
        model: (json['model'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HostInfo && other.deviceType == deviceType && other.model == model;

  @override
  int get hashCode => Object.hash(deviceType, model);
}
