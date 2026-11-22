#!/usr/bin/env python3
"""Regression tests for Rust token masking at lint-policy boundaries."""

import contextlib
import io
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from source_policy_oracle import (
    CargoMetadata,
    manifest_allow_violations,
    run_text,
    rustflag_allow_tokens,
    rust_files,
)


class PolicyHelperTests(unittest.TestCase):
    def test_registered_gitlink_is_not_first_party_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "update-index", "--add", "--cacheinfo",
                 "160000,1111111111111111111111111111111111111111,dependency"],
                check=True,
            )
            (root / "dependency").mkdir()
            (root / "dependency" / "foreign.rs").write_text("", encoding="utf-8")
            (root / "untracked").mkdir()
            own = root / "untracked" / "own.rs"
            own.write_text("", encoding="utf-8")
            self.assertEqual(rust_files([root]), [own.resolve()])

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
