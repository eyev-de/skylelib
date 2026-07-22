# Changelog

## 1.0.0

Initial release, split out of `flutter_eap`.

- All Riverpod providers previously exported by
  `package:flutter_eap/flutter_eap_providers.dart` now live here; import
  `package:flutter_eap_riverpod/flutter_eap_riverpod.dart` instead.
- `flutter_eap` itself is now state-manager agnostic (plain streams only).
- Version stays in lockstep with `flutter_eap` and the skylelib SDK.
