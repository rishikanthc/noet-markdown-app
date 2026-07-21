#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CC_BIN="${CC:-cc}"
CXX_BIN="${CXX:-c++}"
"$CC_BIN" -std=c11 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/c_abi_smoke.c
"$CXX_BIN" -std=c++17 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/cpp_header_smoke.cpp

LIBRARY="${1:-zig-out/lib/libmdcore.a}"
if [[ ! -f "$LIBRARY" ]]; then
  echo "Header ABI checks passed; skipping symbol check because $LIBRARY does not exist"
  exit 0
fi

NM_BIN="${NM:-nm}"
SYMBOLS="$(mktemp)"
trap 'rm -f "$SYMBOLS"' EXIT
"$NM_BIN" -g "$LIBRARY" > "$SYMBOLS"

while IFS= read -r symbol; do
  [[ -z "$symbol" ]] && continue
  if ! grep -Eq "[[:space:]]_?${symbol}$" "$SYMBOLS"; then
    echo "missing exported ABI symbol: $symbol" >&2
    exit 1
  fi
done < tests/expected_symbols.txt

echo "C/C++ header and exported symbol ABI checks passed"
