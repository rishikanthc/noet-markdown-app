#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 -m unittest tests/test_conformance.py
./scripts/verify-abi.sh /dev/null
./scripts/bootstrap-cmark.sh
zig fmt --check build.zig src
zig build test --summary all
./scripts/verify-abi.sh
zig build conformance --summary all
