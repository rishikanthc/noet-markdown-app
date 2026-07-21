#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-xcframework.sh must run on macOS" >&2
  exit 2
fi

for tool in git cmake zig xcodebuild libtool; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing required tool: $tool" >&2
    exit 2
  }
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.29.0.gfm.13"
SRC="$ROOT/vendor/cmark-gfm/src"
ARTIFACTS="$ROOT/artifacts"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/github/cmark-gfm.git "$SRC"
fi

rm -rf "$ARTIFACTS"
mkdir -p "$ARTIFACTS"

build_slice() {
  local zig_target="$1"
  local cmake_arch="$2"
  local name="$3"
  local cmark_build="$ROOT/vendor/cmark-gfm/build-$name"
  local cmark_prefix="$ROOT/vendor/cmark-gfm/install-$name"
  local zig_prefix="$ARTIFACTS/$name"

  cmake -S "$SRC" -B "$cmark_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$cmark_prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_OSX_ARCHITECTURES="$cmake_arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMARK_TESTS=OFF \
    -DCMARK_SHARED=OFF \
    -DCMARK_STATIC=ON
  cmake --build "$cmark_build" --config Release --parallel
  cmake --install "$cmark_build" --config Release

  zig build \
    -Dtarget="$zig_target" \
    -Doptimize=ReleaseFast \
    -Dcmark-prefix="$cmark_prefix" \
    --prefix "$zig_prefix"

  cp "$ROOT/include/module.modulemap" "$zig_prefix/include/module.modulemap"

  # A static library does not absorb its static dependencies during linking.
  # Merge the Zig archive and both cmark-gfm archives so Swift consumers need
  # to link exactly one binary slice.
  libtool -static \
    -o "$zig_prefix/lib/libMdCore.a" \
    "$zig_prefix/lib/libmdcore.a" \
    "$cmark_prefix/lib/libcmark-gfm-extensions.a" \
    "$cmark_prefix/lib/libcmark-gfm.a"
}

build_slice aarch64-macos arm64 macos-arm64
build_slice x86_64-macos x86_64 macos-x86_64

xcodebuild -create-xcframework \
  -library "$ARTIFACTS/macos-arm64/lib/libMdCore.a" \
  -headers "$ARTIFACTS/macos-arm64/include" \
  -library "$ARTIFACTS/macos-x86_64/lib/libMdCore.a" \
  -headers "$ARTIFACTS/macos-x86_64/include" \
  -output "$ARTIFACTS/MdCore.xcframework"

echo "Created $ARTIFACTS/MdCore.xcframework"
