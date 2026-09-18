# Changelog

## Unreleased

### Fixed

- `skyleControlDataStreamProvider` is seeded with the client's cached control
  state when the device already pushed it in the current link session. A
  provider created after that push (the device only pushes on enable and on
  changes) no longer sits in loading until the next change.

## 1.0.0

Initial release, split out of `flutter_skyle`.

- All Riverpod providers previously exported by
  `package:flutter_skyle/flutter_skyle_providers.dart` now live here; import
  `package:flutter_skyle_riverpod/flutter_skyle_riverpod.dart` instead.
- `flutter_skyle` itself is now state-manager agnostic (plain streams only).
- Version stays in lockstep with `flutter_skyle` and the skylelib SDK.
