import 'log_level.dart';

/// A diagnostic message emitted by the EAP client.
///
/// Consumers can subscribe to [EapClient.logStream] to surface these in
/// an in-app console or forward them to their preferred logger.
class EapLogMessage {
  EapLogMessage({
    required this.level,
    required this.source,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Severity of the event.
  final LogLevel level;

  /// Component that produced the message (e.g. "EapClient", "EapClientFfi").
  final String source;

  /// Human-readable message body.
  final String message;

  /// When the message was created (local time).
  final DateTime timestamp;

  @override
  String toString() => '[$source] $message';
}
