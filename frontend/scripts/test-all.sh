#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname -s)" == "Darwin" ]]; then
  "$ROOT/scripts/build-core.sh"
fi

# XCTest ships with full Xcode, not the Command Line Tools. When it is missing we
# still compile the app (a real check) and rely on the Zig suite below for engine
# coverage, rather than failing the whole run.
if xcrun --find xctest >/dev/null 2>&1; then
  swift test --package-path "$ROOT"
else
  echo "note: XCTest unavailable (Command Line Tools only) — running 'swift build' compile check instead of 'swift test'." >&2
  swift build --package-path "$ROOT"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64|aarch64) ZIG_TARGET="aarch64-macos" ;;
    x86_64)        ZIG_TARGET="x86_64-macos" ;;
    *) echo "unsupported host architecture: $(uname -m)" >&2; exit 2 ;;
  esac
  (
    cd "$ROOT/Vendor/mdcore-zig"
    zig build \
      -Dtarget="$ZIG_TARGET" \
      -Dcmark-prefix="$ROOT/Vendor/mdcore-zig/vendor/cmark-gfm/install" \
      test --summary all
  )
fi
