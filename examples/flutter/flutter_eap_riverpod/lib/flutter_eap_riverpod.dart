/// Riverpod providers for the Skyle eye tracker (flutter_eap).
///
/// Import this instead of `package:flutter_eap/flutter_eap.dart` when your
/// app uses Riverpod: it re-exports the full flutter_eap API (client + data
/// models) plus the providers, so a single import covers everything.
///
/// If you use another state manager, depend on `flutter_eap` directly and
/// skip this package.
library flutter_eap_riverpod;

// Full flutter_eap API (EapClient + data models) for convenience.
export 'package:flutter_eap/flutter_eap.dart';

// Riverpod providers
export 'src/eap_providers.dart';
