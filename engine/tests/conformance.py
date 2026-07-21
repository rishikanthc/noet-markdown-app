#!/usr/bin/env python3
"""Run upstream cmark-gfm examples through mdcore-render.

The parser mirrors cmark-gfm's test/spec_tests.py format:
- opening line: 32 backticks followed by " example" and extension names;
- a single dot separates Markdown from expected HTML;
- a line of 32 backticks closes the example;
- the arrow character represents a literal tab.

Only the five formal GFM extensions supported by MdCore are executed. Optional
cmark-gfm extensions outside the formal GFM specification, such as footnotes,
are reported as skipped rather than silently treated as passing.
"""
from __future__ import annotations

import argparse
import dataclasses
import pathlib
import subprocess
import sys
from difflib import unified_diff

FENCE = "`" * 32
SUPPORTED_EXTENSIONS = {
    "table",
    "strikethrough",
    "autolink",
    "tagfilter",
    "tasklist",
}


@dataclasses.dataclass(frozen=True)
class Example:
    number: int
    markdown: str
    html: str
    extensions: tuple[str, ...]
    section: str
    start_line: int
    end_line: int


def parse_examples(path: pathlib.Path) -> list[Example]:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out: list[Example] = []
    state = "text"
    markdown: list[str] = []
    html: list[str] = []
    extensions: tuple[str, ...] = ()
    section = ""
    start_line = 0
    number = 0

    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if state == "text" and stripped.startswith(FENCE + " example"):
            state = "markdown"
            extensions = tuple(stripped[len(FENCE + " example") :].split())
            markdown = []
            html = []
            start_line = line_number
            continue
        if state == "markdown" and stripped == ".":
            state = "html"
            continue
        if state == "html" and stripped == FENCE:
            state = "text"
            number += 1
            out.append(
                Example(
                    number=number,
                    markdown="".join(markdown).replace("→", "\t"),
                    html="".join(html).replace("→", "\t"),
                    extensions=extensions,
                    section=section,
                    start_line=start_line,
                    end_line=line_number,
                )
            )
            continue
        if state == "markdown":
            markdown.append(line)
        elif state == "html":
            html.append(line)
        elif stripped.startswith("#"):
            section = stripped.lstrip("#").strip()

    if state != "text":
        raise ValueError(f"unterminated example in {path}")
    if not out:
        raise ValueError(f"no examples parsed from {path}; fixture format may have changed")
    return out


def effective_extensions(example: Example, all_extensions_default: bool) -> tuple[str, ...]:
    """Resolve which extensions an example should run with.

    Newer cmark-gfm fixtures (extensions.txt) do not annotate each example with
    the extension names; the whole file is meant to run with all GFM extensions
    enabled. For such fixtures we default to the five formal GFM extensions when
    an example carries no explicit annotation.
    """
    if example.extensions:
        return example.extensions
    if all_extensions_default:
        return tuple(sorted(SUPPORTED_EXTENSIONS))
    return ()


def command_for(
    renderer: pathlib.Path, extensions: tuple[str, ...]
) -> list[str]:
    command = [str(renderer), "--unsafe"]
    if not extensions:
        command.append("--commonmark")
    else:
        for extension in extensions:
            command.extend(("--extension", extension))
    return command


def run(
    renderer: pathlib.Path, example: Example, extensions: tuple[str, ...]
) -> tuple[bool, str]:
    proc = subprocess.run(
        command_for(renderer, extensions),
        input=example.markdown.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        return False, f"renderer exited {proc.returncode}: {proc.stderr.decode('utf-8', 'replace')}"

    # cmark-gfm's fixtures use the <IGNORE> sentinel to mark examples whose only
    # requirement is that the renderer does not crash; the output is not checked.
    if example.html.strip() == "<IGNORE>":
        return True, ""

    actual = proc.stdout.decode("utf-8")
    expected = example.html.replace("\r\n", "\n")
    actual = actual.replace("\r\n", "\n")
    if actual == expected:
        return True, ""

    diff = "".join(
        unified_diff(
            expected.splitlines(keepends=True),
            actual.splitlines(keepends=True),
            fromfile="expected HTML",
            tofile="actual HTML",
        )
    )
    return False, diff or f"expected {expected!r}, actual {actual!r}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--renderer", type=pathlib.Path, required=True)
    parser.add_argument("fixtures", nargs="+", type=pathlib.Path)
    args = parser.parse_args()

    failed = 0
    passed = 0
    skipped = 0
    discovered = 0

    for fixture in args.fixtures:
        examples = parse_examples(fixture)
        discovered += len(examples)
        # Fixtures whose examples omit per-example extension annotations (e.g.
        # cmark-gfm's extensions.txt) are meant to run with all GFM extensions.
        all_extensions_default = not any(ex.extensions for ex in examples)
        print(f"{fixture}: {len(examples)} examples discovered")
        for example in examples:
            extensions = effective_extensions(example, all_extensions_default)
            unsupported = set(extensions) - SUPPORTED_EXTENSIONS - {"disabled"}
            # Footnotes are outside the five formal GFM extensions MdCore ships.
            needs_footnotes = "footnote" in example.section.lower()
            if "disabled" in extensions or unsupported or needs_footnotes:
                skipped += 1
                continue
            ok, message = run(args.renderer, example, extensions)
            if ok:
                passed += 1
                continue
            failed += 1
            print(
                f"FAIL {fixture.name} example {example.number} "
                f"({example.section}, lines {example.start_line}-{example.end_line})\n"
                f"extensions={example.extensions}\n{message}",
                file=sys.stderr,
            )

    print(
        f"{passed} passed, {failed} failed, {skipped} skipped, "
        f"{discovered} discovered"
    )
    if passed == 0:
        print("ERROR: no supported examples executed", file=sys.stderr)
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
