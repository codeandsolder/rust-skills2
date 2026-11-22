#!/usr/bin/env python3
"""Differential migration oracle; never part of the consumer runtime."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from source_policy_oracle import lint_attributes

SUMMARY = re.compile(r"\((\d+) Rust files, (\d+) generated lint boundaries, (\d+) suppression attributes\)")


def compare_corpus(module: Path, root: Path) -> bool:
    root = root.resolve()
    tracked = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--", "*.rs"]
    ).decode().split("\0")
    paths = sorted({path for path in tracked if path and (root / path).is_file()})
    expected = []
    size = 0
    start = time.perf_counter()
    for path in paths:
        source = (root / path).read_text(encoding="utf-8")
        size += len(source.encode())
        attributes = [
            {"kind": kind, "lints": lints, "has_reason": reason,
             "line": source.count("\n", 0, offset) + 1}
            for kind, lints, reason, offset in lint_attributes(source)
        ]
        expected.append(["/workspace/" + path, attributes])
    baseline = time.perf_counter() - start
    start = time.perf_counter()
    actual = json.loads(subprocess.check_output(
        ["node", str(ROOT / "policy-wasm/run.mjs"), str(module), str(root), "scan"],
        input=json.dumps(["/workspace/" + path for path in paths]).encode(),
    ))
    elapsed = time.perf_counter() - start
    if actual != expected:
        mismatches = [(old, new) for old, new in zip(expected, actual, strict=True) if old != new]
        for old, new in mismatches[:5]:
            print(f"expected: {old}\nactual: {new}", file=sys.stderr)
        print(f"{root}: {len(mismatches)} disagreements", file=sys.stderr)
        return False
    print(f"{root}: {len(paths)} files, {size:,} bytes, "
          f"{sum(len(a) for _, a in actual)} attributes; "
          f"Python {baseline:.3f}s; WASI {elapsed:.3f}s; {baseline / elapsed:.2f}x",
          flush=True)
    return True


def compare_fixtures(module: Path, toolchain: str) -> bool:
    old_command = [sys.executable, str(ROOT / "checks/source_policy_oracle.py"), "--toolchain", toolchain]
    new_command = ["node", str(ROOT / "policy-wasm/check.mjs"), str(module), toolchain]
    fixtures = sorted((ROOT / "checks/fixtures").glob("strict-ci-*"))
    failures = []
    old_total = 0.0
    new_total = 0.0
    for fixture in fixtures:
        if not (fixture / "Cargo.toml").is_file():
            continue
        start = time.perf_counter()
        old = subprocess.run(old_command, cwd=fixture, capture_output=True, text=True, check=False)
        old_total += time.perf_counter() - start
        start = time.perf_counter()
        new = subprocess.run(new_command, cwd=fixture, capture_output=True, text=True, check=False)
        new_total += time.perf_counter() - start
        old_summary = SUMMARY.search(old.stdout)
        new_summary = SUMMARY.search(new.stdout)
        if old.returncode != new.returncode or (
            old.returncode == 0
            and (old_summary is None or new_summary is None or old_summary.groups() != new_summary.groups())
        ):
            failures.append(fixture.name)
            print(f"{fixture.name}: Python {old.returncode}, WASI {new.returncode}\n"
                  f"old:\n{old.stdout}{old.stderr}\nnew:\n{new.stdout}{new.stderr}",
                  file=sys.stderr)
        else:
            print(f"{fixture.name}: matched exit {old.returncode}", flush=True)
    print(f"Fixture sweep: {len(failures)} mismatches; "
          f"Python {old_total:.3f}s, WASI {new_total:.3f}s")
    return not failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("module", type=Path)
    parser.add_argument("roots", nargs="*", type=Path)
    parser.add_argument("--fixtures", metavar="NIGHTLY")
    args = parser.parse_args()
    module = args.module.resolve()
    success = True
    for root in args.roots:
        success = compare_corpus(module, root) and success
    if args.fixtures:
        success = compare_fixtures(module, args.fixtures) and success
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
