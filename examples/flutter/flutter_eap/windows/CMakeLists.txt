# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

project(flutter_eap_plugin LANGUAGES C CXX)

set(PLUGIN_NAME "flutter_eap_plugin")

# =========================================================================
# Prebuilt skylelib (release artifact)
#
# Links the prebuilt skylelib import library and bundles skylelib.dll instead of
# compiling skylelib from source. The DLL already contains the WinUSB transport,
# so this plugin no longer links winusb/setupapi/cfgmgr32 itself.
#
# Resolution order (first hit wins):
#   1. -DSKYLELIB_DIST=<unzipped sdk>  — explicit override
#   2. <skylelib repo>/dist/<target>   — source-tree development (build_sdk.ps1)
#   3. <plugin>/.skylelib/<version>/<target> — per-version cache, downloaded
#      from the public GitHub release matching the plugin's pubspec version.
#      This is the path taken when consumed as a pub git dependency.
# =========================================================================

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml" _SKYLELIB_PUBSPEC)
string(REGEX MATCH "(^|\n)version:[ \t]*([0-9]+\\.[0-9]+\\.[0-9]+)" _SKYLELIB_VER_MATCH "${_SKYLELIB_PUBSPEC}")
set(SKYLELIB_VERSION "${CMAKE_MATCH_2}")

if(CMAKE_GENERATOR_PLATFORM MATCHES "ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
  set(SKYLELIB_TARGET "win-arm64")
else()
  set(SKYLELIB_TARGET "win-x64")
endif()

if(NOT DEFINED SKYLELIB_DIST)
  set(_SKYLELIB_REPO_DIST "${CMAKE_CURRENT_SOURCE_DIR}/../../../../dist/${SKYLELIB_TARGET}")
  if(EXISTS "${_SKYLELIB_REPO_DIST}/lib/skylelib.lib")
    set(SKYLELIB_DIST "${_SKYLELIB_REPO_DIST}")
  else()
    set(SKYLELIB_DIST "${CMAKE_CURRENT_SOURCE_DIR}/../.skylelib/${SKYLELIB_VERSION}/${SKYLELIB_TARGET}")
    if(NOT EXISTS "${SKYLELIB_DIST}/lib/skylelib.lib")
      if(NOT SKYLELIB_VERSION)
        message(FATAL_ERROR "flutter_eap: could not parse version: from pubspec.yaml")
      endif()
      if(CMAKE_VERSION VERSION_LESS 3.18)
        message(FATAL_ERROR
          "flutter_eap: auto-downloading the skylelib SDK needs CMake 3.18+. "
          "Unzip skylelib-${SKYLELIB_VERSION}-${SKYLELIB_TARGET}.zip yourself and "
          "pass -DSKYLELIB_DIST=<unzipped sdk>.")
      endif()
      set(_SKYLELIB_ASSET "skylelib-${SKYLELIB_VERSION}-${SKYLELIB_TARGET}.zip")
      set(_SKYLELIB_URL "https://github.com/eyev-de/skylelib/releases/download/v${SKYLELIB_VERSION}/${_SKYLELIB_ASSET}")
      set(_SKYLELIB_ZIP "${SKYLELIB_DIST}/${_SKYLELIB_ASSET}")
      message(STATUS "flutter_eap: downloading ${_SKYLELIB_URL}")
      file(DOWNLOAD "${_SKYLELIB_URL}" "${_SKYLELIB_ZIP}" STATUS _SKYLELIB_DL)
      list(GET _SKYLELIB_DL 0 _SKYLELIB_DL_CODE)
      if(NOT _SKYLELIB_DL_CODE EQUAL 0)
        file(REMOVE "${_SKYLELIB_ZIP}")
        message(FATAL_ERROR
          "flutter_eap: download failed: ${_SKYLELIB_URL}\n"
          "Download/unzip the release yourself and pass -DSKYLELIB_DIST=<unzipped sdk>.")
      endif()
      file(ARCHIVE_EXTRACT INPUT "${_SKYLELIB_ZIP}" DESTINATION "${SKYLELIB_DIST}")
      file(REMOVE "${_SKYLELIB_ZIP}")
    endif()
  endif()
endif()
set(SKYLELIB_INCLUDE "${SKYLELIB_DIST}/include")
set(SKYLELIB_IMPLIB  "${SKYLELIB_DIST}/lib/skylelib.lib")
set(SKYLELIB_DLL     "${SKYLELIB_DIST}/bin/skylelib.dll")

if(NOT EXISTS "${SKYLELIB_IMPLIB}")
  message(FATAL_ERROR
    "Prebuilt skylelib.lib not found at:\n  ${SKYLELIB_IMPLIB}\n"
    "Unzip skylelib-<version>-${SKYLELIB_TARGET}.zip into <repo>/dist/${SKYLELIB_TARGET}, "
    "or pass -DSKYLELIB_DIST=<unzipped windows sdk>.")
endif()

# Bridge + C++ Flutter plugin wrapper (skylelib itself comes from the DLL).
add_library(${PLUGIN_NAME} SHARED
  "include/flutter_eap/flutter_eap_plugin_c_api.h"
  "flutter_eap_plugin_c_api.cpp"
  "flutter_eap_plugin.cpp"
  "flutter_eap_plugin.h"
  "flutter_eap_bridge_windows.c"
)

set_source_files_properties("flutter_eap_bridge_windows.c" PROPERTIES LANGUAGE C)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_property(TARGET ${PLUGIN_NAME} PROPERTY C_STANDARD 17)
set_property(TARGET ${PLUGIN_NAME} PROPERTY C_STANDARD_REQUIRED ON)

apply_standard_settings(${PLUGIN_NAME})

# Export ALL C symbols so Dart FFI can look them up via DynamicLibrary.open.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  WINDOWS_EXPORT_ALL_SYMBOLS ON
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${SKYLELIB_INCLUDE}"            # for the headers' own <skylelib/...> includes
  "${SKYLELIB_INCLUDE}/skylelib"   # for the bridge's flat <eap_client.h>, <eap/...>
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  "${SKYLELIB_IMPLIB}"
)

if(MSVC)
  target_compile_options(${PLUGIN_NAME} PRIVATE
    /W3
    /wd4244  # conversion from 'type1' to 'type2', possible loss of data
    /wd4267  # conversion from 'size_t' to 'type', possible loss of data
    /wd4996  # deprecated POSIX name (strdup -> _strdup)
  )
endif()

# =========================================================================
# Bundled libraries — ship skylelib.dll next to the app executable.
# =========================================================================
set(flutter_eap_bundled_libraries
  "${SKYLELIB_DLL}"
  PARENT_SCOPE
)
