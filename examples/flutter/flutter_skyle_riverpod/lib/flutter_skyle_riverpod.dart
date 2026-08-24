/// Riverpod providers for the Skyle eye tracker (flutter_skyle).
///
/// Import this instead of `package:flutter_skyle/flutter_skyle.dart` when your
/// app uses Riverpod: it re-exports the full flutter_skyle API (client + data
/// models) plus the providers, so a single import covers everything.
///
/// If you use another state manager, depend on `flutter_skyle` directly and
/// skip this package.
library;

// Full flutter_skyle API (SkyleClient + data models) for convenience.
export 'package:flutter_skyle/flutter_skyle.dart';

// Riverpod providers
export 'src/skyle_providers.dart';
