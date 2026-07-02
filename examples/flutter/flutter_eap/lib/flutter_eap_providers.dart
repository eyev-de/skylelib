/// Flutter EAP providers only export
///
/// Use this import when you need Riverpod providers.
/// The providers include the singleton EapClient management.
library flutter_eap_providers;

// Main client API
export 'src/eap_client.dart';

// Data models
export 'src/models/models.dart';

// Riverpod providers
export 'src/providers/eap_providers.dart';
