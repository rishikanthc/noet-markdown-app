# noet-app

A native macOS Markdown editor built with Swift, AppKit, TextKit 2, and a Zig
GitHub Flavored Markdown engine.

The repository contains both halves of the application:

- `frontend/` — the native editor, renderer, Swift package, tests, and app-bundle scripts;
- `engine/` — the standalone Zig MdCore implementation, C ABI, tests, and documentation.

## Requirements

- macOS 15 or newer;
- Xcode or Apple Command Line Tools with Swift 6;
- Homebrew;
- Zig 0.16.x;
- CMake and Git.

Install the non-Apple dependencies:

```bash
cd frontend
make bootstrap
```

## Build and run

```bash
cd frontend
make app
open .build/MarkdownLab.app
```

Or build and launch in one command:

```bash
cd frontend
make run
```

The first build downloads the pinned `cmark-gfm` release and produces a local
static MdCore library before SwiftPM links the application.

## Validation

Run the frontend and integration tests:

```bash
cd frontend
swift test
```

Run the complete standalone engine suite, including ABI and upstream
CommonMark/GFM conformance checks:

```bash
cd engine
./scripts/test-all.sh
```

Generated SwiftPM, Zig, CMake, downloaded dependency, and application-bundle
outputs are intentionally excluded from version control.
