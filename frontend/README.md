# MarkdownLab CLI

A minimal native macOS Markdown editor used to exercise the Zig MdCore component end to end.

The project is intentionally **Xcode-project-free**:

- no `.xcodeproj`;
- no workspace;
- no storyboard or nib;
- no Xcode IDE workflow;
- no `xcodebuild` invocation.

Swift Package Manager builds the executable, Zig builds the core, and shell scripts assemble the `.app` bundle.

## Rendering architecture

MarkdownLab is a single-surface, WYSIWYM native editor. The source string stays
in `NSTextStorage`; the frontend only maps the engine's canonical semantic
snapshot into AppKit attributes and TextKit 2 fragments. There is no HTML
preview or second document model to drift out of sync.

Every source edit follows this path:

```text
NSTextView edit in UTF-16
        ↓
Swift converts the range through MdCore
        ↓
md_document_apply_edit
        ↓
md_document_build_canonical_patch
        ↓
canonical semantic snapshot + decoration spans
        ↓
AppKit attributes + TextKit 2 block fragments
```

The Markdown menu also exercises `md_document_plan_command` for strong, emphasis, strikethrough, inline code, links, headings, block quotes, task items, and list indentation.

## Requirements

- macOS 15 or newer;
- Apple Command Line Tools, installed with `xcode-select --install`;
- Homebrew;
- Zig 0.16.x;
- CMake and Git.

The Apple Command Line Tools provide the Swift compiler, macOS SDK, `libtool`, `codesign`, and `open`. The Xcode IDE does not need to be launched or used.

Install the non-Apple dependencies:

```bash
make bootstrap
```

Or install them manually:

```bash
brew install zig cmake
```

## Build and run

From the repository root:

```bash
make app
open .build/MarkdownLab.app
```

Build and launch in one command:

```bash
make run
```

Open a specific Markdown file:

```bash
make run FILE="$HOME/Documents/example.md"
```

The first core build clones the pinned `cmark-gfm` source and compiles it as static libraries.

## Commands

```text
make bootstrap   Install Zig and CMake with Homebrew
make core        Build Zig + cmark-gfm as libMdCore.a
make build       Build the Swift executable
make app         Assemble .build/MarkdownLab.app
make run         Build and launch the app
make test        Run Swift and native-core tests
make clean       Remove generated output
```

Direct SwiftPM use is also supported after `make core`:

```bash
swift build -c debug
swift test
swift run MarkdownLab
```

For a normal GUI launch, prefer `make run` or opening the generated app bundle. Running the bare executable is mainly useful for diagnostics.

## Repository layout

```text
MarkdownLabCLI/
├── Package.swift
├── Makefile
├── Resources/
│   └── Info.plist
├── Sources/
│   ├── CMdCore/                 C module imported by Swift
│   ├── MarkdownLab/             AppKit application and MdCore bridge
│   └── MarkdownLabSupport/      Platform-independent helpers
├── Tests/
│   └── MarkdownLabTests/
├── Vendor/
│   └── mdcore-zig/              Zig core source
└── scripts/
    ├── build-core.sh
    ├── bundle-app.sh
    ├── run-app.sh
    └── test-all.sh
```

## Native linking model

`scripts/build-core.sh` performs four operations:

1. Builds the pinned `cmark-gfm` dependency.
2. Builds the native-host MdCore Zig static library.
3. Merges MdCore and the two cmark archives into one `libMdCore.a`.
4. Places the archive at `.build/mdcore/lib/libMdCore.a`.

`Package.swift` adds that directory to the macOS linker search path and links `MdCore`. Swift sees only the public C header through the `CMdCore` Clang target.

This build is host-architecture only, which is ideal for local development. The separate XCFramework script in the vendored core remains available for universal distribution builds.

## Tests

Run everything available on the current platform:

```bash
make test
```

On macOS this runs:

- Swift helper tests;
- Swift-to-MdCore integration tests;
- Zig unit tests;
- the C ABI smoke test included with MdCore.

The integration tests verify:

- GFM table rendering;
- canonical semantic snapshots;
- revision advancement after a UTF-16 edit containing an emoji;
- Markdown command planning.

## Rendering behavior

- Edits are coalesced and restyled only across the complete affected visual
  blocks, preserving component geometry while typing.
- Markdown markers are hidden outside the active editing context. Callouts and
  fenced code blocks enter source mode as one semantic editing object.
- TextKit 2 fragments render headings, quote rails, code, tables, media, and
  equations without a web view or a duplicate preview model.
- The screen palette, type families, spacing scale, radii, and syntax colors
  are ported directly from `report-renderer/typst-template/template.typ`.
