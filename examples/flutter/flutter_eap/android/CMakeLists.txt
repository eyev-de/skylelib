# CMakeLists.txt for flutter_eap Android plugin
#
# Links the PREBUILT skylelib (libskylelib.so per ABI, from the release pipeline)
# plus the JNI + Dart-FFI bridge. skylelib is not compiled from source here —
# build.gradle resolves (or downloads) the prebuilt SDK and passes it in via
# -DSKYLELIB_DIST.

cmake_minimum_required(VERSION 3.19)

project(flutter_eap LANGUAGES C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Prebuilt skylelib (release artifact) ------------------------------------
# Normally passed by build.gradle; the repo dist/ fallback covers direct use.
if(NOT DEFINED SKYLELIB_DIST)
  set(SKYLELIB_DIST "${CMAKE_CURRENT_SOURCE_DIR}/../../../../dist/android")
endif()
set(SKYLELIB_INCLUDE "${SKYLELIB_DIST}/include")
set(SKYLELIB_LIB "${SKYLELIB_DIST}/jniLibs/${ANDROID_ABI}/libskylelib.so")

if(NOT EXISTS "${SKYLELIB_LIB}")
  message(FATAL_ERROR
    "Prebuilt libskylelib.so not found for ABI '${ANDROID_ABI}' at:\n  ${SKYLELIB_LIB}\n"
    "Unzip skylelib-<version>-android.zip into <repo>/dist/android, or pass "
    "-DSKYLELIB_DIST=<unzipped android sdk>.")
endif()

# Imported prebuilt shared library (bundled via jniLibs.srcDirs in build.gradle).
add_library(skylelib SHARED IMPORTED)
set_target_properties(skylelib PROPERTIES IMPORTED_LOCATION "${SKYLELIB_LIB}")

# --- Bridge (Dart FFI + Kotlin JNI) ------------------------------------------
add_library(flutter_eap SHARED
    src/main/cpp/flutter_eap_bridge.c  # Dart FFI bridge
    src/main/cpp/jni_bridge.c          # Kotlin JNI bridge
)

target_include_directories(flutter_eap PRIVATE
    ${SKYLELIB_INCLUDE}            # for the headers' own <skylelib/...> includes
    ${SKYLELIB_INCLUDE}/skylelib   # for the bridge's flat <eap_client.h>, <eap/...>
)

target_link_libraries(flutter_eap
    skylelib
    log  # Android logging
)

# Export FFI symbols and keep 16 KB ELF page alignment for Google Play (apps
# targeting Android 15+). NDK r28+ aligns to 16 KB by default.
target_link_options(flutter_eap PRIVATE
    "-Wl,--export-dynamic"
    "-Wl,-z,max-page-size=16384"
)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(flutter_eap PRIVATE -O3)
endif()
