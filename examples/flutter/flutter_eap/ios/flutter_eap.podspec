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
Flutter plugin for communicating with Skyle eye tracker via External Accessory Protocol (EAP).
Uses the prebuilt skylelib C library (skylelib.xcframework) for protocol handling
with an FFI bridge to Dart.
                       DESC
  s.homepage         = 'http://eyev.de'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'eyeV GmbH' => 'kw@eyev.de' }
  s.source           = { :path => '.' }

  # Sources live in the Swift Package Manager layout (dual support - the
  # package at flutter_eap/Package.swift compiles the SAME files):
  # - flutter_eap/Sources/flutter_eap/FlutterEapPlugin.swift
  #     (plugin registration + EASession push transport)
  # - flutter_eap/Sources/flutter_eap/OutputStreamManager.swift
  #   flutter_eap/Sources/flutter_eap/BoundedQueue.swift
  #     (backpressured async writer + its queue)
  # - flutter_eap/Sources/flutter_eap_bridge/include/flutter_eap_ios.h
  #     (umbrella header for Swift-C interop)
  # - flutter_eap/Sources/flutter_eap_bridge/skylelib_unity.c
  #     (compiles only the shared Apple FFI bridge and the Skyle Link glue;
  #      skylelib itself is linked prebuilt, see below)
  s.source_files = 'flutter_eap/Sources/**/*.{swift,h,c}'

  s.public_header_files = 'flutter_eap/Sources/flutter_eap_bridge/include/flutter_eap_ios.h'

  s.dependency 'Flutter'
  # Floor of the prebuilt iOS slices (build_sdk.sh: IOS_DEPLOYMENT_TARGET=13.0),
  # matching flutter_eap/Package.swift and Flutter's own iOS minimum.
  s.platform = :ios, '13.0'
  s.frameworks = 'ExternalAccessory'

  # --- Prebuilt skylelib (release-pipeline artifact) ---------------------------
  # Consume skylelib.xcframework instead of compiling skylelib from source (same
  # artifact the SwiftUI example links). Resolution order (see
  # darwin/skylelib_prebuilt.rb): SKYLELIB_DIST env → the skylelib source tree's
  # dist/ → download the GitHub release matching the plugin version into
  # <plugin>/.skylelib/ (pub git dependency path). The xcframework is then
  # copied into ios/flutter_eap/.skylelib/ - INSIDE the Swift package, so the
  # same copy serves as Package.swift's local binaryTarget - and vendored, so
  # CocoaPods links libskylelib.a into the target that performs the final
  # link — required for apps using `use_frameworks! :linkage => :static`, where
  # the pod itself is archived with libtool and pod-level OTHER_LDFLAGS never
  # reach a linker.
  # NOTE: resolve the Flutter plugin symlink to the real location.
  here = File.realpath(__dir__)
  s.vendored_frameworks = skylelib_vendor_xcframework(here, File.join('flutter_eap', '.skylelib'))
  dev = '${PODS_TARGET_SRCROOT}/flutter_eap/.skylelib/skylelib.xcframework/ios-arm64'
  sim = '${PODS_TARGET_SRCROOT}/flutter_eap/.skylelib/skylelib.xcframework/ios-arm64_x86_64-simulator'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Bridge uses flat includes (<eap_client.h>); shipped headers use namespaced
    # (<skylelib/...>). Expose both roots, per SDK slice.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../darwin/Classes"',
    'HEADER_SEARCH_PATHS[sdk=iphoneos*]'        => "\"#{dev}/Headers\" \"#{dev}/Headers/skylelib\" \"${PODS_TARGET_SRCROOT}/../darwin/Classes\"",
    'HEADER_SEARCH_PATHS[sdk=iphonesimulator*]' => "\"#{sim}/Headers\" \"#{sim}/Headers/skylelib\" \"${PODS_TARGET_SRCROOT}/../darwin/Classes\"",
    'GCC_C_LANGUAGE_STANDARD' => 'c17',
    'OTHER_CFLAGS' => '-DEAP_PLATFORM_POSIX',
  }
  s.swift_version = '5.0'
end
