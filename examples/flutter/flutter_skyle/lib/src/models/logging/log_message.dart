import 'log_level.dart';

/// A diagnostic message emitted by the Skyle client.
///
/// Consumers can subscribe to [SkyleClient.logStream] to surface these in
/// an in-app console or forward them to their preferred logger.
class SkyleLogMessage {
  SkyleLogMessage({
    required this.level,
    required this.source,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Severity of the event.
  final LogLevel level;

  /// Component that produced the message (e.g. "SkyleClient", "SkyleClientFfi").
  final String source;

  /// Human-readable message body.
  final String message;

  /// When the message was created (local time).
  final DateTime timestamp;

  @override
  String toString() => '[$source] $message';
}
