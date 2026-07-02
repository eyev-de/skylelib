import 'dart:ffi';

import '../../ffi/ffi_structs.dart';

/// Version response data from device
///
/// Contains device version information including firmware version,
/// serial number, and device characteristics.
class VersionData {
  /// Firmware version string (UTF-8, max 32 bytes)
  final String firmware;

  /// Device serial number (8 bytes, big-endian, unsigned 64-bit)
  final BigInt serial;

  /// Demo device flag
  final bool isDemoDevice;

  /// Device type
  final int deviceType;

  /// Device platform
  final int devicePlatform;

  /// Device generation
  final int deviceGeneration;

  /// EAP protocol version string (e.g. "1.0.0"). Empty string means firmware predates versioning.
  final String protocolVersion;

  const VersionData({
    required this.firmware,
    required this.serial,
    required this.isDemoDevice,
    required this.deviceType,
    required this.devicePlatform,
    required this.deviceGeneration,
    required this.protocolVersion,
  });

  factory VersionData.fromEapVersionResponse(EapVersionResponse version) {
    final firmwareBytes = <int>[];
    for (var i = 0; i < 32; i++) {
      final byte = version.firmware[i];
      if (byte == 0) break; // Stop at null terminator
      firmwareBytes.add(byte);
    }
    final firmwareString = String.fromCharCodes(firmwareBytes);

    final protocolBytes = <int>[];
    for (var i = 0; i < 32; i++) {
      final byte = version.protocolVersion[i];
      if (byte == 0) break; // Stop at null terminator
      protocolBytes.add(byte);
    }
    final protocolString = String.fromCharCodes(protocolBytes);

    // Convert signed int to unsigned BigInt (handles values > 2^63-1)
    final unsignedSerial = BigInt.from(version.serial).toUnsigned(64);

    return VersionData(
      firmware: firmwareString,
      serial: unsignedSerial,
      isDemoDevice: version.isDemoDevice,
      deviceType: version.deviceType,
      devicePlatform: version.devicePlatform,
      deviceGeneration: version.deviceGeneration,
      protocolVersion: protocolString,
    );
  }

  @override
  String toString() {
    return 'VersionData('
        'firmware: $firmware, '
        'serial: $serial, '
        'isDemoDevice: $isDemoDevice, '
        'deviceType: $deviceType, '
        'devicePlatform: $devicePlatform, '
        'deviceGeneration: $deviceGeneration, '
        'protocolVersion: $protocolVersion'
        ')';
  }

  factory VersionData.fromJson(Map<String, dynamic> json) {
    return VersionData(
      firmware: json['firmware'],
      serial: BigInt.parse(json['serial'].toString()),
      isDemoDevice: json['isDemoDevice'],
      deviceType: json['deviceType'],
      devicePlatform: json['devicePlatform'],
      deviceGeneration: json['deviceGeneration'],
      protocolVersion: json['protocolVersion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'firmware': firmware,
      'serial': serial.toString(),
      'isDemoDevice': isDemoDevice,
      'deviceType': deviceType,
      'devicePlatform': devicePlatform,
      'deviceGeneration': deviceGeneration,
      'protocolVersion': protocolVersion,
    };
  }
}
