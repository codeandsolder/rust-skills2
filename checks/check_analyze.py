#!/usr/bin/env python3
"""Cargo evidence must prove each generated example was actually checked."""

import json
from pathlib import Path

from checks import analyze

SOURCE_DIR = Path("/checkout/checks/examples")
MANIFEST = {"sample": {"expect": "compile"}}


def parse(records, manifest=MANIFEST):
    return analyze.parse((json.dumps(record) for record in records), manifest, SOURCE_DIR)


def target(name="sample"):
    return {"name": name, "kind": ["example"], "src_path": str(SOURCE_DIR / f"{name}.rs")}


def artifact(fresh=False):
    return {"reason": "compiler-artifact", "target": target(), "fresh": fresh}


def error():
    return {"reason": "compiler-message", "target": target(),
            "message": {"level": "error", "message": "mismatched types", "code": {"code": "E0308"}}}


def done(success=True):
    return {"reason": "build-finished", "success": success}


def rejected(records, message, manifest=MANIFEST):
    try:
        parse(records, manifest)
    except SystemExit as raised:
        assert message in str(raised), str(raised)
    else:
        raise AssertionError("invalid Cargo evidence accepted")


def main():
    for fresh in (False, True):
        assert parse([artifact(fresh), done()]) == {}
    failed = error()
    assert parse([failed, done(False)])["sample"] == [failed["message"]]
    for records in ([], [artifact()], [artifact(), done(), done()]):
        rejected(records, "exactly one")
    rejected([done()], "did not check")
    warning = error()
    warning["message"]["level"] = "warning"
    rejected([warning, done()], "did not check")
    rejected([error(), done(False)], "missing", {"sample": {}, "missing": {}})
    dependency = error()
    dependency["target"]["kind"] = ["lib"]
    rejected([dependency, done(False)], "outside generated")
    wrong_source = artifact()
    wrong_source["target"]["src_path"] = "/other/sample.rs"
    rejected([wrong_source, done()], "did not check")
    assert parse([done()], {"fixture": {"generated": False}}) == {}
    rejected([artifact(), done(False)], "failed without")
    rejected([error(), done()], "reported success")
    try:
        analyze.parse(['{"reason":'], MANIFEST, SOURCE_DIR)
    except SystemExit as raised:
        assert "invalid Cargo JSON" in str(raised), str(raised)
    else:
        raise AssertionError("malformed JSON accepted")
    print("OK: Cargo evidence validity, completeness, source identity and failure contracts")


if __name__ == "__main__":
    main()
