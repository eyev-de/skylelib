#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_eap.podspec` to validate before publishing.
#
require File.join(File.realpath(__dir__), '..', 'darwin', 'skylelib_prebuilt.rb')

Pod::Spec.new do |s|
  s.name             = 'flutter_eap'
  s.version          = skylelib_pubspec_version(File.expand_path('..', File.realpath(__dir__)))
  s.summary          = 'Flutter EAP plugin for Skyle eye tracker communication.'
  s.description      = <<-DESC
Flutter plugin for communicating with Skyle eye tracker via EAP protocol.
Uses the prebuilt skylelib C library (skylelib.xcframework) for protocol
handling with an FFI bridge to Dart. macOS uses IOKit for USB bulk transfers.
                       DESC
  s.homepage         = 'http://eyev.de'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'eyeV GmbH' => 'kw@eyev.de' }

  s.source           = { :path => '.' }

  # Classes/ contains:
  # - FlutterEapPlugin.swift  (plugin registration + IOKit transport wiring)
  # - flutter_eap_macos.h     (umbrella header for Swift-C interop)
  # - skylelib_unity.c        (compiles only the shared Apple FFI bridge;
  #                            skylelib itself is linked prebuilt, see below)
  s.source_files = 'Classes/**/*.{swift,h,c}'

  s.public_header_files = 'Classes/flutter_eap_macos.h'

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.frameworks = 'IOKit', 'CoreFoundation'

  # --- Prebuilt skylelib (release-pipeline artifact) ---------------------------
  # Consume skylelib.xcframework instead of compiling skylelib from source — the
  # same artifact the SwiftUI example links. Resolution order (see
  # darwin/skylelib_prebuilt.rb): SKYLELIB_DIST env → the skylelib source tree's
  # dist/ → download the GitHub release matching the plugin version into
  # <plugin>/.skylelib/ (the path taken when consumed as a pub git dependency).
  # The xcframework is then copied into macos/.skylelib/ and vendored, so
  # CocoaPods links libskylelib.a into the target that performs the final link
  # (works for both dynamic and static `use_frameworks!` linkage).
  # NOTE: resolve the Flutter plugin symlink (…/ephemeral/.symlinks/plugins/…)
  # to the real vendored location — File.expand_path alone keeps the symlink path.
  here  = File.realpath(__dir__)
  s.vendored_frameworks = skylelib_vendor_xcframework(here)
  slice = '${PODS_TARGET_SRCROOT}/.skylelib/skylelib.xcframework/macos-arm64_x86_64'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Bridge uses flat includes (<eap_client.h>); the shipped headers use
    # namespaced ones (<skylelib/...>). Expose both roots.
    'HEADER_SEARCH_PATHS' => [
      "\"#{slice}/Headers\"",
      "\"#{slice}/Headers/skylelib\"",
      '"${PODS_TARGET_SRCROOT}/../darwin/Classes"',
    ].join(' '),
    'GCC_C_LANGUAGE_STANDARD' => 'c17',
    'OTHER_CFLAGS' => '-DEAP_PLATFORM_POSIX',
  }
  s.swift_version = '5.0'
end
