#!/bin/bash
#
#  IkuraDroid - builds the SDL libraries the iOS port links against.
#
#  Four source releases, built as iOS device (arm64) static libraries into
#  ios-deps/, which is what ios/CMakeLists.txt expects in iOS_DEPS_PREFIX:
#
#    SDL2-2.30.12        libSDL2.a        the same version the Android
#                                         build vendors in app/src/main/jni/sdl
#    SDL2_image-2.8.2    libSDL2_image.a  PNG/JPG through the stb backend
#                                         that ships in the tarball
#    SDL2_ttf-2.22.0     libSDL2_ttf.a    + libfreetype.a (vendored, and
#                                         installed separately, so both are
#                                         linked)
#    SDL2_mixer-2.8.2    libSDL2_mixer.a  WAV/OGG/MP3/FLAC from the vendored
#                                         stb_vorbis/minimp3/dr_flac decoders
#
#  SDL2_gfx is not here on purpose: it has no build system of its own and no
#  upstream release, so ios/CMakeLists.txt compiles the four .c files the
#  Android build already uses (app/src/main/jni/sdl_gfx).
#
#  Needs a macOS host with Xcode - run it locally or let
#  .github/workflows/ios.yml run it.  Run it with IKURA_DEPS_HOST=1 on any
#  other machine and it builds the same option set for the host instead,
#  which is only useful to sanity check the options and the install layout.
#
#  Usage: ios/tools/build-deps.sh [prefix]
#           prefix defaults to <repo>/ios-deps
#
set -euo pipefail

SDL2_VERSION="2.30.12"
SDL_IMAGE_VERSION="2.8.2"
SDL_MIXER_VERSION="2.8.2"
SDL_TTF_VERSION="2.22.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFIX="${1:-${iOS_DEPS_PREFIX:-$ROOT/ios-deps}}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-ios-deps}"
SOURCE_DIR="$BUILD_DIR/src"
DOWNLOAD_DIR="$BUILD_DIR/download"

IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
IOS_ARCHS="${IOS_ARCHS:-arm64}"

if command -v ninja >/dev/null 2>&1; then
	GENERATOR="Ninja"
else
	GENERATOR="Unix Makefiles"
fi
JOBS="$( (command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu) || nproc || echo 4)"

mkdir -p "$PREFIX" "$SOURCE_DIR" "$DOWNLOAD_DIR"

# Progress goes to stderr: fetch and unpack print the path they resolved on
# stdout and that is what the callers capture.
say() { printf '\n=== %s\n' "$*" >&2; }

# ---------------------------------------------------------------- toolchain

TOOLCHAIN_ARGS=()
if [ -z "${IKURA_DEPS_HOST:-}" ]; then
	TOOLCHAIN_ARGS+=(
		"-DCMAKE_SYSTEM_NAME=iOS"
		"-DCMAKE_OSX_SYSROOT=iphoneos"
		"-DCMAKE_OSX_ARCHITECTURES=$IOS_ARCHS"
		"-DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET"
	)
else
	say "IKURA_DEPS_HOST set: building for the host instead of iOS"
fi

CMAKE_COMMON=(
	"-G" "$GENERATOR"
	"-DCMAKE_BUILD_TYPE=Release"
	"-DCMAKE_INSTALL_PREFIX=$PREFIX"
	"-DCMAKE_PREFIX_PATH=$PREFIX"
	"-DBUILD_SHARED_LIBS=OFF"
	"${TOOLCHAIN_ARGS[@]}"
)

# ---------------------------------------------------------------- downloads

fetch() {
	local url="$1" out="$DOWNLOAD_DIR/$(basename "$1")"
	if [ ! -f "$out" ]; then
		say "downloading $(basename "$out")"
		curl -fL --retry 3 --retry-delay 2 -o "$out.part" "$url"
		mv "$out.part" "$out"
	fi
	printf '%s\n' "$out"
}

unpack() {
	local tarball out
	tarball="$(fetch "$1")"
	out="$SOURCE_DIR/$(basename "$tarball" .tar.gz)"
	if [ ! -d "$out" ]; then
		say "unpacking $(basename "$tarball")"
		tar -xzf "$tarball" -C "$SOURCE_DIR"
	fi
	printf '%s\n' "$out"
}

# ---------------------------------------------------------------- building

build_library() {
	local name="$1" source="$2"
	shift 2
	say "configuring $name"
	cmake -S "$source" -B "$BUILD_DIR/$name" "${CMAKE_COMMON[@]}" "$@"
	say "building $name"
	cmake --build "$BUILD_DIR/$name" --parallel "$JOBS"
	say "installing $name"
	cmake --install "$BUILD_DIR/$name"
}

SDL2_DIR="$(unpack "https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.tar.gz")"
IMAGE_DIR="$(unpack "https://github.com/libsdl-org/SDL_image/releases/download/release-$SDL_IMAGE_VERSION/SDL2_image-$SDL_IMAGE_VERSION.tar.gz")"
TTF_DIR="$(unpack "https://github.com/libsdl-org/SDL_ttf/releases/download/release-$SDL_TTF_VERSION/SDL2_ttf-$SDL_TTF_VERSION.tar.gz")"
MIXER_DIR="$(unpack "https://github.com/libsdl-org/SDL_mixer/releases/download/release-$SDL_MIXER_VERSION/SDL2_mixer-$SDL_MIXER_VERSION.tar.gz")"

# SDL2 itself: static only, no test suite. SDL_FRAMEWORK=OFF keeps it a
# plain archive instead of an .xcframework-style bundle.
build_library sdl2 "$SDL2_DIR" \
	-DSDL_SHARED=OFF \
	-DSDL_STATIC=ON \
	-DSDL_FRAMEWORK=OFF \
	-DSDL_TEST=OFF \
	-DSDL_TESTS=OFF

# SDL_image: the stb backend decodes PNG and JPEG from inside the tarball
# (src/stb_image.h), so no libpng/libjpeg build is needed. The ImageIO
# backend is off because it links ApplicationServices, which is a macOS
# framework the iOS SDK does not have. WebP/AVIF/JXL/SVG/TIFF are all off
# for the same reason: they need libraries that are not in the tarball.
build_library sdl2_image "$IMAGE_DIR" \
	-DSDL2IMAGE_VENDORED=OFF \
	-DSDL2IMAGE_BACKEND_STB=ON \
	-DSDL2IMAGE_BACKEND_IMAGEIO=OFF \
	-DSDL2IMAGE_PNG=ON \
	-DSDL2IMAGE_JPG=ON \
	-DSDL2IMAGE_TIF=OFF \
	-DSDL2IMAGE_WEBP=OFF \
	-DSDL2IMAGE_AVIF=OFF \
	-DSDL2IMAGE_JXL=OFF \
	-DSDL2IMAGE_SVG=OFF \
	-DSDL2IMAGE_SAMPLES=OFF \
	-DSDL2IMAGE_TESTS=OFF
# Note for later: games that ship .webp artwork need SDL2IMAGE_WEBP=ON plus
# an iOS build of libwebp installed into the same prefix.

# SDL_ttf: vendored FreeType (external/freetype is in the tarball) and no
# harfbuzz, which keeps the font path to freetype's own shaping - the same
# thing the Android build links (app/src/main/jni/sdl_ttf).
build_library sdl2_ttf "$TTF_DIR" \
	-DSDL2TTF_VENDORED=ON \
	-DSDL2TTF_HARFBUZZ=OFF \
	-DSDL2TTF_SAMPLES=OFF

# SDL_mixer: the vendored decoders cover everything the engine plays -
# stb_vorbis (OGG), minimp3 (MP3), dr_flac (FLAC) and WAV. MOD and MIDI are
# off because their backends (libxmp, timidity) are not in the tarball;
# Android enables them, so a game with .mod/.mid music will be silent here.
build_library sdl2_mixer "$MIXER_DIR" \
	-DSDL2MIXER_VENDORED=ON \
	-DSDL2MIXER_MOD=OFF \
	-DSDL2MIXER_MIDI=OFF \
	-DSDL2MIXER_OPUS=OFF \
	-DSDL2MIXER_WAVPACK=OFF \
	-DSDL2MIXER_GME=OFF \
	-DSDL2MIXER_SAMPLES=OFF

# ---------------------------------------------------------------- check

say "dependencies in $PREFIX"
ls -1 "$PREFIX/lib"
for header in SDL.h SDL_image.h SDL_ttf.h SDL_mixer.h; do
	if [ ! -f "$PREFIX/include/SDL2/$header" ]; then
		echo "ERROR: $PREFIX/include/SDL2/$header is missing" >&2
		exit 1
	fi
done
for library in libSDL2.a libSDL2_image.a libSDL2_ttf.a libfreetype.a libSDL2_mixer.a; do
	if [ ! -f "$PREFIX/lib/$library" ]; then
		echo "ERROR: $PREFIX/lib/$library is missing" >&2
		exit 1
	fi
done
echo "all four SDL libraries (plus vendored freetype) are in place"
