/// Flutter EAP (External Accessory Protocol) client library
///
/// Provides high-performance eye tracking communication using native C library
/// via FFI (Foreign Function Interface).
///
/// Main components:
/// - [EapClient] - High-level API for eye tracking device communication
/// - Data models - [GazeData], [PositioningData], [CalibrationConfig], etc.
/// - Streams - Real-time data streams for gaze, positioning, calibration
///
/// Example usage:
/// ```dart
/// final client = EapClient();
/// await client.initialize();
/// await client.connect();
///
/// // Listen to gaze data
/// client.gazeStream.listen((gaze) {
///   print('Gaze: ${gaze.gazeX}, ${gaze.gazeY}');
/// });
///
/// await client.enableGaze(true);
/// ```
library flutter_eap;

// Main client API
export 'src/eap_client.dart';

// Data models
export 'src/models/models.dart';
