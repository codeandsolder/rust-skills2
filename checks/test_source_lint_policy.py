#!/usr/bin/env python3
"""Regression tests for Rust token masking at lint-policy boundaries."""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.check_source_lint_policy import (
    CargoMetadata,
    lint_attributes,
    manifest_allow_violations,
    mask_noncode,
    run_text,
    rustflag_allow_tokens,
)


class RustTokenTests(unittest.TestCase):
    def test_character_literals_preserve_following_attributes(self) -> None:
        literals = [
            "'\"'",
            "b'\"'",
            r"'\''",
            r"'\\'",
            r"'\x22'",
            r"'\u{22}'",
            "'['",
            "']'",
            "'🦀'",
        ]
        attribute = '#[expect(clippy::too_many_lines, reason = "fixture")]'
        for literal in literals:
            source = f"const C: char = {literal};\n{attribute}\nfn example() {{}}"
            with self.subTest(literal=literal):
                found = lint_attributes(source)
                self.assertEqual(len(found), 1)
                self.assertEqual(
                    found[0][:3], ("expect", ["clippy::too_many_lines"], True)
                )
                self.assertEqual(source.count("\n", 0, found[0][3]), 1)

    def test_lifetimes_and_labels_remain_code(self) -> None:
        source = (
            "fn f<'a>(x: &'a str) -> &'static str { 'outer: loop { break 'outer; } }"
        )
        self.assertEqual(mask_noncode(source), source)

    def test_comments_and_strings_do_not_create_attributes(self) -> None:
        source = """// #[allow(clippy::panic)]
/* nested /* #[warn(clippy::panic)] */ comment */
const S: &str = r###"#[allow(clippy::panic)]"###;
const T: &str = "#[allow(clippy::panic)]";
#[cfg_attr(test, expect(clippy::too_many_lines, reason = "fixture, with comma"))]
fn example() {}
"""
        masked = mask_noncode(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual(masked.count("\n"), source.count("\n"))
        self.assertEqual(
            [item[:3] for item in lint_attributes(source)],
            [("expect", ["clippy::too_many_lines"], True)],
        )


class PolicyHelperTests(unittest.TestCase):
    def test_rustflag_allow_forms_are_detected(self) -> None:
        self.assertEqual(
            rustflag_allow_tokens("-C opt-level=3 -A dead_code"), ["-A dead_code"]
        )
        self.assertEqual(
            rustflag_allow_tokens("-Aclippy::pedantic"), ["-Aclippy::pedantic"]
        )
        self.assertEqual(
            rustflag_allow_tokens("--allow=unused_imports"), ["--allow=unused_imports"]
        )
        self.assertEqual(
            rustflag_allow_tokens("-Copt-level=3\x1f--allow\x1fdead_code"),
            ["--allow dead_code"],
        )
        self.assertEqual(
            rustflag_allow_tokens("-D warnings -C target-cpu=x86-64-v2"), []
        )

    def test_manifest_allow_levels_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "Cargo.toml"
            manifest.write_text(
                "[workspace]\n"
                'resolver = "3"\n\n'
                "[workspace.lints.clippy]\n"
                'missing_errors_doc = "allow"\n'
                'too_many_lines = { level = "deny", priority = 0 }\n',
                encoding="utf-8",
            )
            metadata: CargoMetadata = {
                "workspace_root": str(root),
                "workspace_members": [],
                "packages": [],
            }
            violations = manifest_allow_violations(metadata)
            self.assertEqual(len(violations), 1)
            self.assertIn("missing_errors_doc = allow is forbidden", violations[0])


class CommandCaptureTests(unittest.TestCase):
    def test_success_keeps_stderr_out_of_structured_stdout(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            output = run_text(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('warning: fixture', file=sys.stderr); print('{\"ok\": true}')",
                ]
            )

        self.assertEqual(output, '{"ok": true}\n')
        self.assertEqual(stderr.getvalue(), "warning: fixture\n")

    def test_failure_reports_both_streams(self) -> None:
        stderr = io.StringIO()
        with (
            contextlib.redirect_stderr(stderr),
            self.assertRaisesRegex(SystemExit, "2"),
        ):
            run_text(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('out'); print('err', file=sys.stderr); raise SystemExit(3)",
                ]
            )

        diagnostics = stderr.getvalue()
        self.assertIn("rust-skills2: command failed:", diagnostics)
        self.assertIn("err\n", diagnostics)
        self.assertIn("out\n", diagnostics)


if __name__ == "__main__":
    unittest.main()
