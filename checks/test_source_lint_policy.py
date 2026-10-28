#!/usr/bin/env python3
"""Regression tests for Rust token masking at lint-policy boundaries."""
import contextlib
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_source_lint_policy import lint_attributes, mask_noncode, run_text


class RustTokenTests(unittest.TestCase):
    def test_character_literals_preserve_following_attributes(self):
        literals = ["'\"'", "b'\"'", r"'\''", r"'\\'", r"'\x22'", r"'\u{22}'", "'['", "']'", "'🦀'"]
        attribute = '#[allow(clippy::unwrap_used, reason = "fixture")]'
        for literal in literals:
            source = f"const C: char = {literal};\n{attribute}\nfn example() {{}}"
            with self.subTest(literal=literal):
                found = lint_attributes(source)
                self.assertEqual(len(found), 1)
                self.assertEqual(found[0][:3], ("allow", ["clippy::unwrap_used"], True))
                self.assertEqual(source.count("\n", 0, found[0][3]), 1)

    def test_lifetimes_and_labels_remain_code(self):
        source = "fn f<'a>(x: &'a str) -> &'static str { 'outer: loop { break 'outer; } }"
        self.assertEqual(mask_noncode(source), source)

    def test_comments_and_strings_do_not_create_attributes(self):
        source = '''// #[allow(clippy::panic)]
/* nested /* #[warn(clippy::panic)] */ comment */
const S: &str = r###"#[allow(clippy::panic)]"###;
const T: &str = "#[allow(clippy::panic)]";
#[cfg_attr(test, expect(clippy::too_many_lines, reason = "fixture, with comma"))]
fn example() {}
'''
        masked = mask_noncode(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual(masked.count("\n"), source.count("\n"))
        self.assertEqual([item[:3] for item in lint_attributes(source)],
                         [("expect", ["clippy::too_many_lines"], True)])


class CommandCaptureTests(unittest.TestCase):
    def test_success_keeps_stderr_out_of_structured_stdout(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            output = run_text([
                sys.executable,
                "-c",
                "import sys; print('warning: fixture', file=sys.stderr); print('{\"ok\": true}')",
            ])

        self.assertEqual(output, '{"ok": true}\n')
        self.assertEqual(stderr.getvalue(), "warning: fixture\n")

    def test_failure_reports_both_streams(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaisesRegex(SystemExit, "2"):
            run_text([
                sys.executable,
                "-c",
                "import sys; print('out'); print('err', file=sys.stderr); raise SystemExit(3)",
            ])

        diagnostics = stderr.getvalue()
        self.assertIn("rust-skills2: command failed:", diagnostics)
        self.assertIn("err\n", diagnostics)
        self.assertIn("out\n", diagnostics)


if __name__ == "__main__":
    unittest.main()
