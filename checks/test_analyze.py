#!/usr/bin/env python3
"""Cargo evidence must prove each generated example was actually checked."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import analyze


class CargoEvidenceTests(unittest.TestCase):
    def parse(self, records, manifest=None):
        if manifest is None:
            manifest = {"sample": {"expect": "compile"}}
        with tempfile.TemporaryDirectory() as tmp, patch.object(analyze, "manifest", manifest):
            path = Path(tmp) / "check.json"
            path.write_text("\n".join(json.dumps(record) for record in records))
            return analyze.parse(path)

    def target(self, name="sample"):
        return {"name": name, "kind": ["example"],
                "src_path": str(analyze.HERE / "examples" / f"{name}.rs")}

    def artifact(self, fresh=False):
        return {"reason": "compiler-artifact", "target": self.target(), "fresh": fresh}

    def error(self):
        return {"reason": "compiler-message", "target": self.target(),
                "message": {"level": "error", "message": "mismatched types", "code": {"code": "E0308"}}}

    def done(self, success=True):
        return {"reason": "build-finished", "success": success}

    def test_success_and_cached_success(self):
        for fresh in (False, True):
            self.assertEqual(self.parse([self.artifact(fresh), self.done()]), {})

    def test_expected_compile_failure_has_evidence(self):
        self.assertIn("sample", self.parse([self.error(), self.done(False)]))

    def test_no_evidence_and_truncation_fail(self):
        for records in ([], [self.done()], [self.artifact()], [self.artifact(), self.done(), self.done()]):
            with self.subTest(records=records), self.assertRaises(SystemExit):
                self.parse(records)

    def test_warnings_are_not_success(self):
        warning = self.error()
        warning["message"]["level"] = "warning"
        with self.assertRaisesRegex(SystemExit, "did not check"):
            self.parse([warning, self.done()])

    def test_partial_build_fails(self):
        with self.assertRaisesRegex(SystemExit, "missing"):
            self.parse([self.error(), self.done(False)], {"sample": {}, "missing": {}})

    def test_dependency_error_is_not_example_failure(self):
        error = self.error()
        error["target"]["kind"] = ["lib"]
        with self.assertRaisesRegex(SystemExit, "outside generated"):
            self.parse([error, self.done(False)])

    def test_same_name_wrong_source_is_not_evidence(self):
        artifact = self.artifact()
        artifact["target"]["src_path"] = "/other/sample.rs"
        with self.assertRaisesRegex(SystemExit, "did not check"):
            self.parse([artifact, self.done()])

    def test_non_generated_examples_do_not_require_artifacts(self):
        self.assertEqual(self.parse([self.done()], {"fixture": {"generated": False}}), {})

    def test_inconsistent_completion_fails(self):
        for records in ([self.artifact(), self.done(False)], [self.error(), self.done()]):
            with self.subTest(records=records), self.assertRaises(SystemExit):
                self.parse(records)

    def test_malformed_json_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "check.json"
            path.write_text('{"reason":')
            with self.assertRaisesRegex(SystemExit, "invalid Cargo JSON"):
                analyze.parse(path)


if __name__ == "__main__":
    unittest.main()
