# Changelog

## 1.0.0

Initial release, split out of `flutter_skyle`.

- All Riverpod providers previously exported by
  `package:flutter_skyle/flutter_skyle_providers.dart` now live here; import
  `package:flutter_skyle_riverpod/flutter_skyle_riverpod.dart` instead.
- `flutter_skyle` itself is now state-manager agnostic (plain streams only).
- Version stays in lockstep with `flutter_skyle` and the skylelib SDK.
