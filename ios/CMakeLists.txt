cmake_minimum_required(VERSION 3.20)

#  IkuraDroid - iOS port build.
#
#  Two targets:
#
#    ikura_engine   the ViLE engine + its 3rd party code as a static
#                   library. Same wildcard source collection the NDK
#                   build uses (app/src/main/jni/vile/Android.mk), so a
#                   new engine .cpp is picked up automatically here too.
#    ikuradroid     the app bundle: the UIKit host plus the engine.
#
#  Dependencies (SDL2, SDL2_image, SDL2_ttf, SDL2_mixer) come from the
#  iOS_DEPS_PREFIX cache variable - ios/tools/build-deps.sh fills that
#  directory with arm64 device builds. SDL2_gfx has no build system of
#  its own, so its four sources are compiled straight into the engine
#  from app/src/main/jni/sdl_gfx (the same 1.0.1 sources the Android
#  build links).
#
#  Typical invocation (GitHub Actions, ios.yml):
#
#    cmake -G Xcode -S ios -B build-ios \
#          -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
#          -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
#          -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
#          -DiOS_DEPS_PREFIX=$PWD/ios-deps

project(ikuradroid-ios LANGUAGES C CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
	message(FATAL_ERROR
		"ios/CMakeLists.txt builds the iOS port only: pass "
		"-DCMAKE_SYSTEM_NAME=iOS (see the comment at the top of this file).")
endif()

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)	# the engine uses GCC-style extensions

if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
	set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "" FORCE)
endif()
# Architecture is left to whichever default (arm64) the caller picked:
# CMAKE_OSX_ARCHITECTURES=arm64 also covers the simulator on Apple
# silicon, so the same build directory type-checks both.

set(IKURA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(VILE_DIR   "${IKURA_ROOT}/app/src/main/jni/vile")

if(NOT iOS_DEPS_PREFIX)
	set(iOS_DEPS_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/ios-deps" CACHE PATH
		"Directory holding iOS builds of SDL2/SDL2_image/SDL2_ttf/SDL2_mixer")
endif()
message(STATUS "iOS dependency prefix: ${iOS_DEPS_PREFIX}")

# ---------------------------------------------------------------- engine

file(GLOB_RECURSE VILE_SOURCES CONFIGURE_DEPENDS
	"${VILE_DIR}/*.cpp"
	"${VILE_DIR}/*.c")

# media/hh is the engine's FFMPEG playback path. It never shipped in this
# port - media/vplmpeg.cpp plays the same streams with pl_mpeg - and its
# headers are not vendored, so the Android build does not compile it
# either (app/src/main/jni/vile/Android.mk lists media/*.cpp only).
list(FILTER VILE_SOURCES EXCLUDE REGEX "/media/hh/")

file(GLOB VILE_GFX_SOURCES CONFIGURE_DEPENDS
	"${IKURA_ROOT}/app/src/main/jni/sdl_gfx/*.c")

add_library(ikura_engine STATIC ${VILE_SOURCES} ${VILE_GFX_SOURCES})

target_include_directories(ikura_engine PUBLIC
	"${VILE_DIR}"
	"${iOS_DEPS_PREFIX}/include"
	"${iOS_DEPS_PREFIX}/include/SDL2")

target_compile_definitions(ikura_engine PUBLIC
	# The engine's POSIX/desktop branch - the same switch the Android
	# build makes, minus Android. VILE_ARCH_LINUX is what the engine
	# itself tests for (it predates the Linux name for the "POSIX
	# desktop" flavour of the code).
	VILE_ARCH_LINUX
	# Selects the iOS branches added by this port (UIApplication host,
	# app-private save directory, no exit confirmation, ...).
	VILE_IOS=1
	# Without this, SDL_main.h turns main() into SDL_main() on iOS (which
	# is how the Android port is entered: SDLActivity calls the method
	# name SDL_main through JNI). This app has a main() of its own, so
	# the engine's main() is kept and renamed instead - see
	# set_source_files_properties(vile.cpp) below.
	SDL_MAIN_HANDLED=1
	# main() becomes vile_engine_main() so the app's own main() (and its
	# UIKit library screen) can sit in front of the engine. The engine
	# keeps its plain blocking main loop - the host calls it on the main
	# thread. Only set for the engine source below.
)

# Keep the engine quiet about the usual 3rd party sins, but keep it
# strict enough to catch porting mistakes. The vendored copy of SDL_gfx
# predates modern clang and needs the extra relaxations.
target_compile_options(ikura_engine PRIVATE
	-Wno-deprecated-declarations
	-Wno-unknown-pragmas)

set_source_files_properties(${VILE_GFX_SOURCES} PROPERTIES
	COMPILE_OPTIONS "-Wno-everything")

# libfreetype.a is listed because SDL2_ttf builds its vendored freetype as a
# library of its own (ios/tools/build-deps.sh installs both): TTF_* symbols
# live in libSDL2_ttf.a, the FT_* ones behind them in libfreetype.a.
target_link_libraries(ikura_engine PUBLIC
	"${iOS_DEPS_PREFIX}/lib/libSDL2.a"
	"${iOS_DEPS_PREFIX}/lib/libSDL2_image.a"
	"${iOS_DEPS_PREFIX}/lib/libSDL2_ttf.a"
	"${iOS_DEPS_PREFIX}/lib/libfreetype.a"
	"${iOS_DEPS_PREFIX}/lib/libSDL2_mixer.a")

# The frameworks SDL2 itself links on iOS (SDL2-2.30.12/CMakeLists.txt,
# EXTRA_LDFLAGS): a static libSDL2.a does not carry them, so the app has to
# name them. OpenGLES is needed even though the app renders through Metal -
# SDL's renderer driver table references the ES2 backend. CoreHaptics and
# GameController are weak-linked inside SDL; listing them here is harmless.
find_library(FRAMEWORK_AVFOUNDATION AVFoundation)
find_library(FRAMEWORK_AUDIOTOOLBOX AudioToolbox)
find_library(FRAMEWORK_COREBLUETOOTH CoreBluetooth)
find_library(FRAMEWORK_COREGRAPHICS CoreGraphics)
find_library(FRAMEWORK_COREMOTION CoreMotion)
find_library(FRAMEWORK_COREAUDIO CoreAudio)
find_library(FRAMEWORK_COREHAPTICS CoreHaptics)
find_library(FRAMEWORK_COREVIDEO CoreVideo)
find_library(FRAMEWORK_METAL Metal)
find_library(FRAMEWORK_OPENGLES OpenGLES)
find_library(FRAMEWORK_GAME_CONTROLLER GameController)
find_library(FRAMEWORK_QUARTZCORE QuartzCore)
find_library(FRAMEWORK_FOUNDATION Foundation)
find_library(FRAMEWORK_UIKIT UIKit)

target_link_libraries(ikura_engine PUBLIC
	z
	"${FRAMEWORK_AVFOUNDATION}"
	"${FRAMEWORK_AUDIOTOOLBOX}"
	"${FRAMEWORK_COREBLUETOOTH}"
	"${FRAMEWORK_COREGRAPHICS}"
	"${FRAMEWORK_COREMOTION}"
	"${FRAMEWORK_COREAUDIO}"
	"${FRAMEWORK_COREHAPTICS}"
	"${FRAMEWORK_COREVIDEO}"
	"${FRAMEWORK_METAL}"
	"${FRAMEWORK_OPENGLES}"
	"${FRAMEWORK_GAME_CONTROLLER}"
	"${FRAMEWORK_QUARTZCORE}"
	"${FRAMEWORK_FOUNDATION}"
	"${FRAMEWORK_UIKIT}")

# ------------------------------------------------------------------- app

# Objective-C throughout: the host is where SDL and the C++ engine meet
# (IkuraHost.mm), and mixing Swift into a command line CMake build would
# add a bridging header and a language mode to get right - for a library
# screen that is a table view and three buttons.
set(IKURA_APP_SOURCES
	"${CMAKE_CURRENT_SOURCE_DIR}/main.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/IkuraAppDelegate.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/IkuraGameLibrary.m"
	"${CMAKE_CURRENT_SOURCE_DIR}/IkuraHost.mm")

add_executable(ikuradroid MACOSX_BUNDLE ${IKURA_APP_SOURCES})

set_target_properties(ikuradroid PROPERTIES
	OUTPUT_NAME "IkuraDroid"
	MACOSX_BUNDLE_BUNDLE_NAME "IkuraDroid"
	MACOSX_BUNDLE_GUI_IDENTIFIER "su.viende.ikuradroid"
	MACOSX_BUNDLE_BUNDLE_VERSION "1"
	MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
	MACOSX_BUNDLE_INFO_PLIST
		"${CMAKE_CURRENT_SOURCE_DIR}/ikura_ios_Info.plist.in"
	# No storyboard, no asset catalog: the UI is built in code so the
	# whole app is reviewable as source.
)

# main() must not be renamed: it is the app's own entry point. Only
# vile.cpp (the engine's main) gets the rename treatment.
set_source_files_properties("${VILE_DIR}/vile.cpp" PROPERTIES
	COMPILE_DEFINITIONS "main=vile_engine_main")

target_link_libraries(ikuradroid PRIVATE ikura_engine)

target_link_options(ikuradroid PRIVATE
	"-Wl,-no_warn_duplicate_libraries")

# The game font the Android app ships as app/src/main/assets/default.ttf:
# same file, copied into the bundle. The engine looks it up when the
# game folder has no default.ttf of its own (vile.cpp, VILE_IOS branch).
set(IKURA_FONT "${IKURA_ROOT}/app/src/main/assets/default.ttf")
if(EXISTS "${IKURA_FONT}")
	set_source_files_properties("${IKURA_FONT}" PROPERTIES
		MACOSX_PACKAGE_LOCATION "Resources")
	target_sources(ikuradroid PRIVATE "${IKURA_FONT}")
else()
	message(WARNING "app/src/main/assets/default.ttf missing - the iOS app "
		"will only work with games that bring their own font")
endif()

# Xcode specifics: the app is meant to be built unsigned in CI and then
# pseudo-signed with ldid, so turn off every signing/notarisation step
# and keep the build from trying to reach the App Store.
set_target_properties(ikuradroid PROPERTIES
	XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
	XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
	XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
	XCODE_ATTRIBUTE_EXPANDED_CODE_SIGN_IDENTITY ""
	XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
	XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH "NO"
	XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}"
	XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
	XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES"
	XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD "gnu++11")
