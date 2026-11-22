#!/usr/bin/env python3
"""Compare portable workspace selection with the previous resolver and real Cargo."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "checks" / "fixtures"


def main() -> int:
    module = Path(sys.argv[1]).resolve()
    toolchain = sys.argv[2]
    previous = ROOT / "checks" / "workspace_test_policy_oracle.py"
    if not previous.exists():
        previous = ROOT / "scripts" / "workspace_test_policy.py"
    cases = [
        ("strict-ci-pass", "false", []),
        ("strict-ci-pass", "true", ["--workspace"]),
        ("strict-ci-workspace-overrides", "false", []),
        ("strict-ci-workspace-overrides", "false", ["--workspace"]),
        ("strict-ci-workspace-overrides", "true", ["--workspace"]),
        ("strict-ci-workspace-overrides", "false", ["--package=legacy-member"]),
        ("strict-ci-workspace-overrides", "false", ["-p", "strict-member@0.1.0"]),
        (
            "strict-ci-workspace-overrides",
            "false",
            ["--workspace", "--exclude", "legacy-member"],
        ),
        ("strict-ci-workspace-overrides", "false", ["-p", "missing"]),
        (
            "strict-ci-workspace-overrides",
            "false",
            ["--workspace", "--exclude=missing"],
        ),
        ("strict-ci-workspace-default-panics", "false", ["--workspace"]),
        ("strict-ci-workspace-default-panics", "true", ["--workspace"]),
    ]
    for fixture, default, selectors in cases:
        directory = FIXTURES / fixture
        old = subprocess.run(
            [
                sys.executable,
                str(previous),
                "--toolchain",
                toolchain,
                "--default-allow-test-panics",
                default,
                *[f"--cargo-arg={arg}" for arg in selectors],
            ],
            cwd=directory,
            capture_output=True,
            text=True,
            check=False,
        )
        new = subprocess.run(
            [
                "node",
                str(ROOT / "policy-wasm" / "check.mjs"),
                str(module),
                toolchain,
                default,
                *selectors,
            ],
            cwd=directory,
            capture_output=True,
            text=True,
            check=False,
        )
        if (old.returncode, old.stdout) != (new.returncode, new.stdout):
            print(
                f"{fixture} {selectors}: {old.returncode=} {new.returncode=}\n"
                f"{old.stdout}\n{old.stderr}\n{new.stdout}\n{new.stderr}",
                file=sys.stderr,
            )
            return 1
    # The old resolver incorrectly narrowed --workspace + --package. Check
    # the intended behavior against Cargo's actual selected unit graph.

    directory = FIXTURES / "strict-ci-workspace-overrides"
    selectors = ["--workspace", "-p", "strict-member"]
    graph = json.loads(
        subprocess.check_output(
            [
                "cargo",
                f"+{toolchain}",
                "check",
                *selectors,
                "--locked",
                "--all-targets",
                "--unit-graph",
                "-Z",
                "unstable-options",
            ],
            cwd=directory,
        )
    )
    roots = {graph["units"][index]["pkg_id"] for index in graph["roots"]}
    metadata = json.loads(
        subprocess.check_output(
            [
                "cargo",
                f"+{toolchain}",
                "metadata",
                "--no-deps",
                "--format-version",
                "1",
            ],
            cwd=directory,
        )
    )
    expected = {
        f"{member['name']}@{member['version']}"
        for member in metadata["packages"]
        if member["id"] in roots
    }
    actual = subprocess.check_output(
        [
            "node",
            str(ROOT / "policy-wasm" / "check.mjs"),
            str(module),
            toolchain,
            "false",
            *selectors,
        ],
        cwd=directory,
        text=True,
    )
    assert {line.split("\t")[1] for line in actual.splitlines()} == expected
    assert set(actual.splitlines()) == {
        "strict\tstrict-member@0.1.0",
        "relaxed\tlegacy-member@0.1.0",
    }
    print(
        f"Workspace policy: {len(cases)} differential cases and Cargo unit-graph parity passed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
