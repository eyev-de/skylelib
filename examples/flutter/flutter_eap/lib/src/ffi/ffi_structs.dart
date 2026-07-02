// FFI struct definitions matching C message structures
// These structs match the C definitions byte-for-byte

import 'dart:ffi';

// =============================================================================
// Basic Types (from eap_types.h)
// =============================================================================

/// Point with float coordinates (8 bytes)
final class EapPointf extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;
}

/// Size with float dimensions (8 bytes)
final class EapSizef extends Struct {
  @Float()
  external double width;

  @Float()
  external double height;
}

/// Size with uint16 dimensions (4 bytes)
final class EapSizeu extends Struct {
  @Uint16()
  external int width;

  @Uint16()
  external int height;
}

/// Rectangle with uint16 coordinates (8 bytes)
final class EapRectu extends Struct {
  @Uint16()
  external int top;

  @Uint16()
  external int left;

  @Uint16()
  external int bottom;

  @Uint16()
  external int right;
}

/// Rectangle with float coordinates (16 bytes)
/// Maps to C# Rect2d.Bytes(): Top, Left (X), Bottom, Right (Y) as floats
final class EapRectf extends Struct {
  @Float()
  external double top; // byte 0-3

  @Float()
  external double left; // byte 4-7

  @Float()
  external double bottom; // byte 8-11

  @Float()
  external double right; // byte 12-15
}

/// Rotated rectangle (20 bytes)
final class EapRotatedRect extends Struct {
  external EapPointf center; // 8 bytes
  external EapSizef size; // 8 bytes

  @Float()
  external double angle; // 4 bytes
}

// =============================================================================
// EAP Message Header (from eap_types.h)
// =============================================================================

/// EAP message header - included in all response/message structs
/// Matches C eap_message_header struct layout (with platform-specific padding)
final class EapMessageHeader extends Struct {
  @Uint16()
  external int messageType; // 2 bytes - EAP message type

  @Uint16()
  external int payloadLength; // 2 bytes - payload length

  @Int64()
  external int timestampMs; // 8 bytes - Unix timestamp in milliseconds

  @Bool()
  external bool hasTimestamp; // 1 byte - true if header included timestamp
}

// =============================================================================
// Gaze Messages (from gaze_messages.h)
// =============================================================================

/// Gaze movement type
abstract class EapGazeType {
  static const int fixation = 0;
  static const int saccade = 1;
  static const int unknown = 2;
}

/// Complex gaze data (17 bytes)
final class EapComplexGaze extends Struct {
  external EapPointf raw; // 8 bytes - raw gaze position
  external EapPointf smoothed; // 8 bytes - smoothed gaze position (USE THIS)

  @Uint8()
  external int type; // 1 byte - movement type (EapGazeType)
}

/// Gaze response message (header + 51 bytes payload)
final class EapGazeResponse extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp
  external EapComplexGaze left; // 17 bytes - left eye gaze
  external EapComplexGaze right; // 17 bytes - right eye gaze
  external EapComplexGaze both; // 17 bytes - combined gaze (MOST ACCURATE)
}

// =============================================================================
// Positioning Messages (from positioning_messages.h)
// =============================================================================

/// Complex feature (pupil/glint) (44 bytes)
final class EapComplexFeature extends Struct {
  external EapPointf center; // 8 bytes
  external EapRectf boundingRect; // 16 bytes
  external EapRotatedRect ellipse; // 20 bytes
}

/// Complex iris landmarks (44 bytes)
final class EapComplexIris extends Struct {
  external EapPointf center; // 8 bytes
  external EapPointf top; // 8 bytes
  external EapPointf left; // 8 bytes
  external EapPointf right; // 8 bytes
  external EapPointf bottom; // 8 bytes

  @Float()
  external double distanceMm; // 4 bytes
}

/// Complex eye data (184 bytes)
final class EapComplexEye extends Struct {
  external EapRectu boundingRect; // 8 bytes
  external EapComplexFeature pupil; // 44 bytes
  external EapComplexFeature leftGlint; // 44 bytes
  external EapComplexFeature rightGlint; // 44 bytes
  external EapComplexIris iris; // 44 bytes
}

/// Complex eyes (both eyes) (368 bytes)
final class EapComplexEyes extends Struct {
  external EapComplexEye left; // 184 bytes
  external EapComplexEye right; // 184 bytes
}

/// Complex face data (384 bytes)
final class EapComplexFace extends Struct {
  external EapRectf boundingRect; // 16 bytes
  external EapComplexEyes eyes; // 368 bytes
}

/// Positioning response message (header + 384 bytes payload)
final class EapPositioningResponse extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp
  external EapComplexFace face; // 384 bytes
}

// =============================================================================
// Version Messages (from version_messages.h)
// =============================================================================

/// Version response message (header + 76 bytes payload)
final class EapVersionResponse extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp

  @Array(32)
  external Array<Uint8> firmware; // 32 bytes - firmware version string (may not be null-terminated)

  @Uint64()
  external int serial; // 8 bytes - device serial number (big-endian)

  @Bool()
  external bool isDemoDevice; // 1 byte

  @Uint8()
  external int deviceType; // 1 byte

  @Uint8()
  external int devicePlatform; // 1 byte

  @Uint8()
  external int deviceGeneration; // 1 byte

  @Array(32)
  external Array<Uint8> protocolVersion; // 32 bytes - EAP protocol version string (empty if firmware predates versioning)
}

// =============================================================================
// Control Messages (from control_messages.h)
// =============================================================================

/// Control message (header + 10 bytes payload)
final class EapControlMessage extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp

  @Bool()
  external bool isStandbyEnabled; // byte 0

  @Bool()
  external bool isAutoPauseEnabled; // byte 1

  @Bool()
  external bool isPauseEnabled; // byte 2

  @Uint8()
  external int trackingMode; // byte 3

  @Uint8()
  external int gazeFilter; // byte 4 (0-255)

  @Uint8()
  external int fixationFilter; // byte 5 (0-255)

  @Bool()
  external bool isAssistiveTouchEnabled; // byte 6

  @Bool()
  external bool showTrackingDetails; // byte 7

  @Bool()
  external bool isHidEnabled; // byte 8

  @Bool()
  external bool isEthernetEnabled; // byte 9
}

/// Set display info message (12 bytes payload, matches eap_set_display_info)
/// App -> Device; type 0x00E2.
final class EapSetDisplayInfo extends Struct {
  external EapSizeu resolution; // 4 bytes
  external EapSizef sizeMm;     // 8 bytes
}

// =============================================================================
// Calibration Messages (from calibration_messages.h)
// =============================================================================

final class EapConfigureCalibration extends Struct {
  @Uint16()
  external int pointsCount; // 2 bytes - number of calibration points
  external Pointer<Uint8> points; // array of point indices
  @Uint16()
  external int coordinatesCount; // 2 bytes - number of custom coordinates
  external Pointer<EapPointf> coordinates; // pointer to custom coordinates
  external EapSizeu resolution; // screen resolution in pixels
  external EapSizef size; // physical screen size in mm
  @Bool()
  external bool improve; // improve existing calibration
}

/// Quality point (14 bytes)
final class EapCalibrationQualityPoint extends Struct {
  @Uint8()
  external int index; // 1 byte

  external EapPointf accuracy; // 8 bytes - offset to calibration point

  @Float()
  external double precision; // 4 bytes - precision in radius

  @Uint8()
  external int quality; // 1 byte - quality rating 0-255
}

/// Next calibration point message (header + 9 bytes payload)
final class EapNextCalibrationPoint extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp

  @Uint8()
  external int index; // 1 byte

  external EapPointf point; // 8 bytes - point coordinates in screen pixels
}

/// Collecting calibration points progress message (header + 2 bytes payload)
final class EapCollectingCalibrationPoints extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp

  @Uint8()
  external int index; // 1 byte

  @Uint8()
  external int progress; // 1 byte (0-100)
}

/// Finished calibration message (variable length)
/// Note: The quality point arrays are allocated dynamically
/// and must be accessed via pointers.
final class EapFinishedCalibration extends Struct {
  external EapMessageHeader header; // EAP message header with timestamp

  @Uint16()
  external int leftCount; // 2 bytes - number of left eye quality points

  external Pointer<EapCalibrationQualityPoint> left; // pointer to left eye quality points

  @Uint16()
  external int rightCount; // 2 bytes - number of right eye quality points

  external Pointer<EapCalibrationQualityPoint> right; // pointer to right eye quality points
}
