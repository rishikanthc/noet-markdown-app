# Validation record

Date: 2026-07-19

## Checks executed in the delivery environment

The following checks completed successfully:

```text
python3 -m unittest tests/test_conformance.py
python3 -m py_compile tests/conformance.py tests/test_conformance.py
bash -n scripts/bootstrap-cmark.sh scripts/build-xcframework.sh scripts/test-all.sh scripts/verify-abi.sh
cc -std=c11 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/c_abi_smoke.c
c++ -std=c++17 -Wall -Wextra -Werror -Iinclude -fsyntax-only tests/cpp_header_smoke.cpp
./scripts/verify-abi.sh /dev/null
```

Results:

- fixture-parser tests: 3 passed;
- shell scripts: syntax valid;
- public header: valid C11 and C++17;
- expected ABI declaration set: present.

## Checks requiring Zig and the pinned dependency

The delivery environment did not contain a Zig compiler and could not download
one because outbound dependency downloads were unavailable. Therefore these
commands are configured but were not executed here:

```text
./scripts/bootstrap-cmark.sh
zig fmt --check build.zig src
zig build test --summary all
zig build conformance --summary all
./scripts/verify-abi.sh
```

The GitHub Actions workflow runs those checks on Linux and macOS using Zig
0.16.0. A release should not be tagged until that workflow passes, including all
supported examples from the upstream `spec.txt` and `extensions.txt` fixtures.
