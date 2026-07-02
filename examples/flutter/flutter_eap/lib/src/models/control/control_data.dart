/// Control state and settings of the device

/// Tracking mode
enum TrackingMode {
  binocular(0),
  left(1),
  right(2);

  final int value;
  const TrackingMode(this.value);

  static TrackingMode fromValue(int value) {
    switch (value) {
      case 0:
        return TrackingMode.binocular;
      case 1:
        return TrackingMode.left;
      case 2:
        return TrackingMode.right;
      default:
        return TrackingMode.binocular;
    }
  }
}

/// Complete control message from device
class ControlMessage {
  /// Standby mode enabled
  final bool isStandbyEnabled;

  /// Auto-pause enabled
  final bool isAutoPauseEnabled;

  /// Pause enabled
  final bool isPauseEnabled;

  /// Tracking mode (0-2)
  final TrackingMode trackingMode;

  /// Gaze filter strength (0-255)
  final int gazeFilter;

  /// Fixation filter strength (0-255)
  final int fixationFilter;

  /// Assistive touch enabled
  final bool isAssistiveTouchEnabled;

  /// Show tracking details
  final bool showTrackingDetails;

  /// HID mode enabled
  final bool isHidEnabled;

  /// Ethernet enabled
  final bool isEthernetEnabled;

  const ControlMessage({
    required this.isStandbyEnabled,
    required this.isAutoPauseEnabled,
    required this.isPauseEnabled,
    required this.trackingMode,
    required this.gazeFilter,
    required this.fixationFilter,
    required this.isAssistiveTouchEnabled,
    required this.showTrackingDetails,
    required this.isHidEnabled,
    required this.isEthernetEnabled,
  });

  factory ControlMessage.empty() => ControlMessage(
    isStandbyEnabled: false,
    isAutoPauseEnabled: false,
    isPauseEnabled: false,
    trackingMode: TrackingMode.binocular,
    gazeFilter: 0,
    fixationFilter: 0,
    isAssistiveTouchEnabled: false,
    showTrackingDetails: false,
    isHidEnabled: false,
    isEthernetEnabled: false,
  );

  @override
  String toString() =>
      'ControlMessage('
      'tracking=$trackingMode, '
      'gazeFilter=$gazeFilter, '
      'fixationFilter=$fixationFilter, '
      'pause=$isPauseEnabled, '
      'standby=$isStandbyEnabled,'
      'autoPause=$isAutoPauseEnabled, '
      'assistiveTouch=$isAssistiveTouchEnabled, '
      'showTrackingDetails=$showTrackingDetails, '
      'hid=$isHidEnabled, '
      'ethernet=$isEthernetEnabled'
      ')';

  ControlData copyWith({
    bool? isStandbyEnabled,
    bool? isAutoPauseEnabled,
    bool? isPauseEnabled,
    TrackingMode? trackingMode,
    int? gazeFilter,
    int? fixationFilter,
    bool? isAssistiveTouchEnabled,
    bool? showTrackingDetails,
    bool? isHidEnabled,
    bool? isEthernetEnabled,
  }) {
    return ControlData(
      isStandbyEnabled: isStandbyEnabled ?? this.isStandbyEnabled,
      isAutoPauseEnabled: isAutoPauseEnabled ?? this.isAutoPauseEnabled,
      isPauseEnabled: isPauseEnabled ?? this.isPauseEnabled,
      trackingMode: trackingMode ?? this.trackingMode,
      gazeFilter: gazeFilter ?? this.gazeFilter,
      fixationFilter: fixationFilter ?? this.fixationFilter,
      isAssistiveTouchEnabled: isAssistiveTouchEnabled ?? this.isAssistiveTouchEnabled,
      showTrackingDetails: showTrackingDetails ?? this.showTrackingDetails,
      isHidEnabled: isHidEnabled ?? this.isHidEnabled,
      isEthernetEnabled: isEthernetEnabled ?? this.isEthernetEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isStandbyEnabled': isStandbyEnabled,
      'isAutoPauseEnabled': isAutoPauseEnabled,
      'isPauseEnabled': isPauseEnabled,
      'trackingMode': trackingMode.value,
      'gazeFilter': gazeFilter,
      'fixationFilter': fixationFilter,
      'isAssistiveTouchEnabled': isAssistiveTouchEnabled,
      'showTrackingDetails': showTrackingDetails,
      'isHidEnabled': isHidEnabled,
      'isEthernetEnabled': isEthernetEnabled,
    };
  }

  factory ControlMessage.fromJson(Map<String, dynamic> json) {
    return ControlMessage(
      isStandbyEnabled: json['isStandbyEnabled'] as bool,
      isAutoPauseEnabled: json['isAutoPauseEnabled'] as bool,
      isPauseEnabled: json['isPauseEnabled'] as bool,
      trackingMode: TrackingMode.fromValue(json['trackingMode'] as int),
      gazeFilter: json['gazeFilter'] as int,
      fixationFilter: json['fixationFilter'] as int,
      isAssistiveTouchEnabled: json['isAssistiveTouchEnabled'] as bool,
      showTrackingDetails: json['showTrackingDetails'] as bool,
      isHidEnabled: json['isHidEnabled'] as bool,
      isEthernetEnabled: json['isEthernetEnabled'] as bool,
    );
  }
}

// Backwards compatibility alias
typedef ControlData = ControlMessage;
