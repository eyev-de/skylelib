// FFI struct definitions matching C message structures
// These structs match the C definitions byte-for-byte

import 'dart:ffi';

// =============================================================================
// Basic Types (from skyle_types.h)
// =============================================================================

/// Point with float coordinates (8 bytes)
final class SkylePointf extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;
}

/// Size with float dimensions (8 bytes)
final class SkyleSizef extends Struct {
  @Float()
  external double width;

  @Float()
  external double height;
}

/// Size with uint16 dimensions (4 bytes)
final class SkyleSizeu extends Struct {
  @Uint16()
  external int width;

  @Uint16()
  external int height;
}

/// Rectangle with uint16 coordinates (8 bytes)
final class SkyleRectu extends Struct {
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
final class SkyleRectf extends Struct {
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
final class SkyleRotatedRect extends Struct {
  external SkylePointf center; // 8 bytes
  external SkyleSizef size; // 8 bytes

  @Float()
  external double angle; // 4 bytes
}

// =============================================================================
// Skyle Message Header (from skyle_types.h)
// =============================================================================

/// Skyle message header - included in all response/message structs
/// Matches C skyle_message_header struct layout (with platform-specific padding)
final class SkyleMessageHeader extends Struct {
  @Uint16()
  external int messageType; // 2 bytes - message type

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
abstract class SkyleGazeType {
  static const int fixation = 0;
  static const int saccade = 1;
  static const int unknown = 2;
}

/// Complex gaze data (17 bytes)
final class SkyleComplexGaze extends Struct {
  external SkylePointf raw; // 8 bytes - raw gaze position
  external SkylePointf smoothed; // 8 bytes - smoothed gaze position (USE THIS)

  @Uint8()
  external int type; // 1 byte - movement type (SkyleGazeType)
}

/// Gaze response message (header + 51 bytes payload)
final class SkyleGazeResponse extends Struct {
  external SkyleMessageHeader header; // message header with timestamp
  external SkyleComplexGaze left; // 17 bytes - left eye gaze
  external SkyleComplexGaze right; // 17 bytes - right eye gaze
  external SkyleComplexGaze both; // 17 bytes - combined gaze (MOST ACCURATE)
}

// =============================================================================
// Positioning Messages (from positioning_messages.h)
// =============================================================================

/// Complex feature (pupil/glint) (44 bytes)
final class SkyleComplexFeature extends Struct {
  external SkylePointf center; // 8 bytes
  external SkyleRectf boundingRect; // 16 bytes
  external SkyleRotatedRect ellipse; // 20 bytes
}

/// Complex iris landmarks (44 bytes)
final class SkyleComplexIris extends Struct {
  external SkylePointf center; // 8 bytes
  external SkylePointf top; // 8 bytes
  external SkylePointf left; // 8 bytes
  external SkylePointf right; // 8 bytes
  external SkylePointf bottom; // 8 bytes

  @Float()
  external double distanceMm; // 4 bytes
}

/// Complex eye data (184 bytes)
final class SkyleComplexEye extends Struct {
  external SkyleRectu boundingRect; // 8 bytes
  external SkyleComplexFeature pupil; // 44 bytes
  external SkyleComplexFeature leftGlint; // 44 bytes
  external SkyleComplexFeature rightGlint; // 44 bytes
  external SkyleComplexIris iris; // 44 bytes
}

/// Complex eyes (both eyes) (368 bytes)
final class SkyleComplexEyes extends Struct {
  external SkyleComplexEye left; // 184 bytes
  external SkyleComplexEye right; // 184 bytes
}

/// Complex face data (384 bytes)
final class SkyleComplexFace extends Struct {
  external SkyleRectf boundingRect; // 16 bytes
  external SkyleComplexEyes eyes; // 368 bytes
}

/// Positioning response message (header + 384 bytes payload)
final class SkylePositioningResponse extends Struct {
  external SkyleMessageHeader header; // message header with timestamp
  external SkyleComplexFace face; // 384 bytes
}

// =============================================================================
// Version Messages (from version_messages.h)
// =============================================================================

/// Version response message (header + 76 bytes payload)
final class SkyleVersionResponse extends Struct {
  external SkyleMessageHeader header; // message header with timestamp

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
  external Array<Uint8> protocolVersion; // 32 bytes - protocol version string (empty if firmware predates versioning)
}

// =============================================================================
// Control Messages (from control_messages.h)
// =============================================================================

/// Control message (header + 10 bytes payload)
final class SkyleControlMessage extends Struct {
  external SkyleMessageHeader header; // message header with timestamp

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

/// Set display info message (12 bytes payload, matches skyle_set_display_info)
/// App -> Device; type 0x00E2.
final class SkyleSetDisplayInfo extends Struct {
  external SkyleSizeu resolution; // 4 bytes
  external SkyleSizef sizeMm;     // 8 bytes
}

// =============================================================================
// Calibration Messages (from calibration_messages.h)
// =============================================================================

final class SkyleConfigureCalibration extends Struct {
  @Uint16()
  external int pointsCount; // 2 bytes - number of calibration points
  external Pointer<Uint8> points; // array of point indices
  @Uint16()
  external int coordinatesCount; // 2 bytes - number of custom coordinates
  external Pointer<SkylePointf> coordinates; // pointer to custom coordinates
  external SkyleSizeu resolution; // screen resolution in pixels
  external SkyleSizef size; // physical screen size in mm
  @Bool()
  external bool improve; // improve existing calibration
}

/// Quality point (14 bytes)
final class SkyleCalibrationQualityPoint extends Struct {
  @Uint8()
  external int index; // 1 byte

  external SkylePointf accuracy; // 8 bytes - offset to calibration point

  @Float()
  external double precision; // 4 bytes - precision in radius

  @Uint8()
  external int quality; // 1 byte - quality rating 0-255
}

/// Next calibration point message (header + 9 bytes payload)
final class SkyleNextCalibrationPoint extends Struct {
  external SkyleMessageHeader header; // message header with timestamp

  @Uint8()
  external int index; // 1 byte

  external SkylePointf point; // 8 bytes - point coordinates in screen pixels
}

/// Collecting calibration points progress message (header + 2 bytes payload)
final class SkyleCollectingCalibrationPoints extends Struct {
  external SkyleMessageHeader header; // message header with timestamp

  @Uint8()
  external int index; // 1 byte

  @Uint8()
  external int progress; // 1 byte (0-100)
}

/// Finished calibration message (variable length)
/// Note: The quality point arrays are allocated dynamically
/// and must be accessed via pointers.
final class SkyleFinishedCalibration extends Struct {
  external SkyleMessageHeader header; // message header with timestamp

  @Uint16()
  external int leftCount; // 2 bytes - number of left eye quality points

  external Pointer<SkyleCalibrationQualityPoint> left; // pointer to left eye quality points

  @Uint16()
  external int rightCount; // 2 bytes - number of right eye quality points

  external Pointer<SkyleCalibrationQualityPoint> right; // pointer to right eye quality points
}
