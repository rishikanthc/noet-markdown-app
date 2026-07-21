#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-core.sh must run on macOS" >&2
  exit 2
fi

for tool in git cmake zig libtool; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing required tool: $tool" >&2
    exit 2
  }
done

ZIG_VERSION="$(zig version)"
if [[ "$ZIG_VERSION" != 0.16.* && "$ZIG_VERSION" != 0.17.* ]]; then
  echo "MdCore expects Zig 0.16.x or 0.17.x; found $ZIG_VERSION" >&2
  exit 2
fi

# Match the Swift toolchain's target so the static library links cleanly.
# The Zig compiler may itself be an x86_64 build running under Rosetta, so we
# resolve the target from the host CPU rather than from the compiler binary.
# Pin the minimum macOS version so the objects match the Swift deployment
# target (macOS 13) and the linker stays quiet.
MACOS_MIN="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
case "$(uname -m)" in
  arm64|aarch64) ZIG_TARGET="aarch64-macos.${MACOS_MIN}" ;;
  x86_64)        ZIG_TARGET="x86_64-macos.${MACOS_MIN}" ;;
  *) echo "unsupported host architecture: $(uname -m)" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/Vendor/mdcore-zig"
OUTPUT="$ROOT/.build/mdcore"
ZIG_PREFIX="$OUTPUT/zig"
CMARK_PREFIX="$CORE/vendor/cmark-gfm/install"

"$CORE/scripts/bootstrap-cmark.sh"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/lib" "$OUTPUT/include"

(
  cd "$CORE"
  zig build \
    -Dtarget="$ZIG_TARGET" \
    -Doptimize=ReleaseFast \
    -Dcmark-prefix="$CMARK_PREFIX" \
    --prefix "$ZIG_PREFIX"
)

libtool -static \
  -o "$OUTPUT/lib/libMdCore.a" \
  "$ZIG_PREFIX/lib/libmdcore.a" \
  "$CMARK_PREFIX/lib/libcmark-gfm-extensions.a" \
  "$CMARK_PREFIX/lib/libcmark-gfm.a"

cp "$CORE/include/mdcore.h" "$OUTPUT/include/mdcore.h"
printf '%s\n' "Built $OUTPUT/lib/libMdCore.a"
