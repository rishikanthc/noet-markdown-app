#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.29.0.gfm.13"
SRC="$ROOT/vendor/cmark-gfm/src"
BUILD="$ROOT/vendor/cmark-gfm/build"
PREFIX="$ROOT/vendor/cmark-gfm/install"

# The dependency checkout is intentionally generated from its pinned tag.
mkdir -p "$(dirname "$SRC")"

for tool in git cmake; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing required tool: $tool" >&2
    exit 2
  }
done

if [[ -d "$SRC/.git" ]]; then
  current="$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || true)"
  if [[ "$current" != "$VERSION" ]]; then
    echo "replacing cmark-gfm checkout at $current with pinned $VERSION" >&2
    rm -rf "$SRC" "$BUILD" "$PREFIX"
  fi
fi

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/github/cmark-gfm.git "$SRC"
fi

# CMake caches absolute paths. Recreate generated state after moving a clone.
if [[ -f "$BUILD/CMakeCache.txt" ]]; then
  cached_build="$(awk -F= '/^CMAKE_CACHEFILE_DIR:INTERNAL=/{ print $2; exit }' "$BUILD/CMakeCache.txt")"
  cached_source="$(awk -F= '/^CMAKE_HOME_DIRECTORY:INTERNAL=/{ print $2; exit }' "$BUILD/CMakeCache.txt")"
  if [[ "$cached_build" != "$BUILD" || "$cached_source" != "$SRC" ]]; then
    echo "discarding stale cmark-gfm CMake cache from a different checkout path" >&2
    rm -rf "$BUILD"
  fi
fi

cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMARK_TESTS=OFF \
  -DCMARK_SHARED=OFF \
  -DCMARK_STATIC=ON
cmake --build "$BUILD" --config Release --parallel
cmake --install "$BUILD" --config Release

echo "Installed cmark-gfm $VERSION into $PREFIX"
