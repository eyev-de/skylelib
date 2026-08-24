#!/usr/bin/env bash
# Vendor skylelib.xcframework into the flutter_skyle Apple Swift packages
# (macos/flutter_skyle/.skylelib/ and ios/flutter_skyle/.skylelib/) so each
# Package.swift's local binaryTarget is used instead of the GitHub release
# download.
#
# CocoaPods users never need this: `pod install` of the matching podspec creates
# the same copy as a side effect. Run this only for pure-SPM setups (Swift
# Package Manager enabled in the Flutter tool, no pod install - which is how the
# bundled example app builds on both Apple platforms), or to refresh the copy
# after rebuilding skylelib (`./scripts/build_sdk.sh xcframework` in the
# skylelib repo).
#
# Usage: vendor_xcframework.sh [macos|ios ...]      (default: both)
#
# Resolution order matches the podspecs (darwin/skylelib_prebuilt.rb):
#   1. SKYLELIB_DIST env (unzipped release containing skylelib.xcframework)
#   2. the skylelib source tree's dist/
#   3. download the GitHub release matching the plugin's pubspec version
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  PLATFORMS="$*"
else
  PLATFORMS="macos ios"
fi

for platform in $PLATFORMS; do
  case "$platform" in
    macos|ios) ;;
    *) echo "flutter_skyle: unknown platform '$platform' (expected macos or ios)" >&2; exit 2 ;;
  esac

  ruby -e "
    require File.join('$PLUGIN_DIR', 'darwin', 'skylelib_prebuilt.rb')
    rel = skylelib_vendor_xcframework(File.join('$PLUGIN_DIR', '$platform'), File.join('flutter_skyle', '.skylelib'))
    puts \"flutter_skyle: vendored #{File.join('$PLUGIN_DIR', '$platform', rel)}\"
  "
done

echo "flutter_skyle: done. If Xcode already resolved a package against the"
echo "GitHub release, re-resolve (flutter clean, or Xcode: File > Packages >"
echo "Reset Package Caches) so the local copy takes effect."
