/// Skyle models only export
///
/// Use this import when you only need data models without the providers.
/// This prevents accidental provider initialization in overlay windows.
library;

// Data models only - no providers, no client
export 'src/models/models.dart';
