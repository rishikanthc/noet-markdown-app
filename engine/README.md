# MdCore

MdCore is the native Zig half of the Markdown editor architecture. It owns revisioned UTF-8 source, provides a stable C ABI for Swift, delegates canonical parsing/rendering to pinned `cmark-gfm`, and emits semantic nodes plus source-backed decoration spans for a TextKit 2 frontend.

## What is implemented

- Formal GitHub Flavored Markdown semantics with all five GFM extensions enabled by default:
  - tables;
  - task-list items;
  - strikethrough;
  - extended autolinks;
  - tag filtering.
- Optional CommonMark-only or explicitly selected-extension documents.
- Strict UTF-8 validation and UTF-8 boundary checks for every edit/command range.
- Revision-checked document replacement edits.
- UTF-8 byte ↔ UTF-16 conversion, including batch conversion for TextKit patches.
- Canonical semantic-node snapshots derived from `cmark-gfm`.
- Source-backed decoration spans for headings, emphasis, strong, strike, code spans/fences, links/images, block quotes, list markers, task markers, tables, HTML, and thematic breaks.
- Markdown-aware source command planning for emphasis, strong, strike, inline code, links, headings, block quotes, task items, and list indentation.
- Safe-by-default HTML plus explicit unsafe HTML and plaintext rendering.
- A versioned C ABI, C module map, C/C++ ABI checks, and macOS XCFramework packaging script.
- Zig unit tests, C integration tests, fixture-parser tests, and an upstream CommonMark/GFM conformance runner.

`cmark-gfm` is the semantic authority. Source-locator output is exact where delimiters can be recovered safely and remains conservative elsewhere; nodes carry `MD_NODE_FLAG_RANGE_APPROXIMATE` rather than inventing positions.

## Dependency versions

- Zig: `0.16.0`
- `cmark-gfm`: `0.29.0.gfm.13`
- macOS deployment target used by the XCFramework script: `13.0` by default

The cmark dependency is private to the implementation. Swift sees only `include/mdcore.h`.

## Build and test

```bash
./scripts/bootstrap-cmark.sh
zig build
zig build test --summary all
zig build conformance --summary all
./scripts/verify-abi.sh
```

Run all checks:

```bash
./scripts/test-all.sh
```

The bootstrap script installs static cmark archives under `vendor/cmark-gfm/install`. The conformance step runs the upstream `spec.txt` and `extensions.txt` examples using each example's declared extension set and unsafe-rendering mode, matching cmark-gfm's own fixture semantics.

## Command-line renderer

```bash
printf '%s\n' '| A | B |' '| - | - |' '| 1 | 2 |' | zig build run
printf '# Hello\n' | ./zig-out/bin/mdcore-render
./zig-out/bin/mdcore-render --commonmark input.md
./zig-out/bin/mdcore-render -e table -e tasklist input.md
```

## C / Swift boundary

All public source positions are UTF-8 byte offsets. Cocoa conversion is explicit:

```c
MdStatus md_document_byte_ranges_to_utf16(
    const MdDocument *document,
    const MdByteRange *byte_ranges,
    size_t count,
    MdUtf16Range *out_ranges
);
```

A normal editor transaction is:

1. Apply the native text mutation immediately.
2. Call `md_document_apply_edit` with the same UTF-8 replacement and expected revision.
3. Use the fast patch to invalidate the affected source lines.
4. Build a canonical patch on the document's serial analysis queue.
5. Discard the patch if its revision is stale.
6. Batch-convert decoration ranges to UTF-16 and apply them in one TextKit transaction.

Command APIs never mutate presentation. They return owned source edits:

```c
MdStatus md_document_plan_command(
    const MdDocument *document,
    uint64_t revision,
    MdCommandKind command,
    MdByteRange selection,
    const MdCommandOptions *options,
    MdEditList **out_edits
);
```

Views returned by a patch, buffer, or edit list remain valid only until the corresponding release function is called.

## macOS XCFramework

On macOS with Xcode installed:

```bash
./scripts/build-xcframework.sh
```

This builds arm64 and x86_64 slices, merges MdCore and both private cmark archives into one static library per slice, and writes:

```text
artifacts/MdCore.xcframework
```

The installed module map makes the framework importable from Swift as `MdCore`.

## Correctness and performance boundary

This repository implements the complete canonical Zig component and public integration contract. Canonical GFM parsing currently snapshots a contiguous source buffer and canonical patches contain a full semantic snapshot. The API intentionally separates fast invalidation from canonical analysis, so a future piece tree and incremental parser can replace those internals without changing Swift or the C ABI.

The following are intentionally not claimed by this version:

- sublinear edits for multi-hundred-megabyte files;
- incremental semantic parsing equivalent to cmark-gfm;
- stable node identities across arbitrary edits;
- arbitrary non-GFM extensions such as footnotes;
- the separate Swift/AppKit renderer.

See `docs/architecture.md` for the full end-to-end design and `docs/c-api.md` for the ownership contract.
