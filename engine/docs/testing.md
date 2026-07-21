# Testing strategy

## Local checks

```bash
python3 -m unittest tests/test_conformance.py
./scripts/bootstrap-cmark.sh
zig fmt --check build.zig src
zig build test --summary all
zig build conformance --summary all
./scripts/verify-abi.sh
```

## Coverage

- `src/utf.zig`: malformed UTF-8, scalar boundaries, surrogate-pair boundaries, round trips.
- `src/source_map.zig`: LF, CRLF, CR, Unicode byte columns.
- `src/document.zig`: revisions, edit boundaries, limits, extension modes, deterministic edit sequences.
- `src/source_locator.zig`: delimiter/content recovery and marker-span bounds.
- `src/commands.zig`: inline/block transformations, escaping, indentation, invalid input, ownership.
- `src/parser.zig`: all formal GFM extensions, CommonMark-only behavior, node/span invariants.
- `tests/c_abi_smoke.c`: end-to-end C ownership, render, patches, conversions, command planning, stale revisions.
- `tests/cpp_header_smoke.cpp`: C++ compatibility and layout checks.
- `tests/conformance.py`: exact upstream fixture execution.
- `scripts/verify-abi.sh`: expected exported-symbol set.

## Conformance rule

The conformance runner fails if it discovers no examples or executes no supported examples. Optional cmark extensions outside formal GFM are reported as skipped; they are never counted as passing.
