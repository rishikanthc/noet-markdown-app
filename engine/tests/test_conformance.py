from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest
import sys

MODULE_PATH = pathlib.Path(__file__).with_name("conformance.py")
SPEC = importlib.util.spec_from_file_location("mdcore_conformance", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
conformance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = conformance
SPEC.loader.exec_module(conformance)


class ConformanceFixtureTests(unittest.TestCase):
    def test_parses_examples_extensions_tabs_and_sections(self) -> None:
        fixture = (
            "# Tables\n"
            + conformance.FENCE
            + " example table\n"
            + "a→b\n"
            + ".\n"
            + "<p>a→b</p>\n"
            + conformance.FENCE
            + "\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "spec.txt"
            path.write_text(fixture, encoding="utf-8")
            examples = conformance.parse_examples(path)

        self.assertEqual(1, len(examples))
        self.assertEqual(("table",), examples[0].extensions)
        self.assertEqual("a\tb\n", examples[0].markdown)
        self.assertEqual("<p>a\tb</p>\n", examples[0].html)
        self.assertEqual("Tables", examples[0].section)

    def test_rejects_fixture_without_examples(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "empty.txt"
            path.write_text("# Empty\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "no examples"):
                conformance.parse_examples(path)

    def test_builds_exact_extension_command(self) -> None:
        example = conformance.Example(
            number=1,
            markdown="",
            html="",
            extensions=("table", "tasklist"),
            section="",
            start_line=1,
            end_line=2,
        )
        command = conformance.command_for(
            pathlib.Path("renderer"), example.extensions
        )
        self.assertEqual(
            [
                "renderer",
                "--unsafe",
                "--extension",
                "table",
                "--extension",
                "tasklist",
            ],
            command,
        )


if __name__ == "__main__":
    unittest.main()
