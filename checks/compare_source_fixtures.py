#!/usr/bin/env python3
"""Compare native-host policy fixtures against the independent CPython oracle."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SUMMARY = re.compile(r"\((\d+) Rust files, (\d+) generated lint boundaries, (\d+) suppression attributes\)")


def compare_fixtures(modules: list[Path], toolchain: str) -> bool:
    old_command = [sys.executable, "-B", str(ROOT / "checks/source_policy_oracle.py"), "--toolchain", toolchain]
    commands = [
        ["node", str(ROOT / "policy-wasm/check.mjs"), str(module), toolchain]
        for module in modules
    ]
    fixtures = sorted((ROOT / "checks/fixtures").glob("strict-ci-*"))
    failures = [0] * len(modules)
    old_total = 0.0
    new_totals = [0.0] * len(modules)
    for fixture in fixtures:
        if not (fixture / "Cargo.toml").is_file():
            continue
        start = time.perf_counter()
        old = subprocess.run(old_command, cwd=fixture, capture_output=True, text=True, check=False)
        old_total += time.perf_counter() - start
        old_summary = SUMMARY.search(old.stdout)
        for index, command in enumerate(commands):
            start = time.perf_counter()
            new = subprocess.run(command, cwd=fixture, capture_output=True, text=True, check=False)
            new_totals[index] += time.perf_counter() - start
            new_summary = SUMMARY.search(new.stdout)
            if old.returncode != new.returncode or (
                old.returncode == 0
                and (old_summary is None or new_summary is None or old_summary.groups() != new_summary.groups())
            ):
                failures[index] += 1
                print(f"{modules[index]} {fixture.name}: Python {old.returncode}, WASI {new.returncode}\n"
                      f"old:\n{old.stdout}{old.stderr}\nnew:\n{new.stdout}{new.stderr}", file=sys.stderr)
            else:
                print(f"{modules[index]} {fixture.name}: matched exit {old.returncode}", flush=True)
    print(f"Native reference fixture sweep: Python {old_total:.3f}s")
    for module, elapsed, count in zip(modules, new_totals, failures, strict=True):
        print(f"{module}: {count} mismatches, WASI {elapsed:.3f}s")
    return not any(failures)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("toolchain")
    parser.add_argument("modules", nargs="+", type=Path)
    args = parser.parse_args()
    return 0 if compare_fixtures([module.resolve() for module in args.modules], args.toolchain) else 1


if __name__ == "__main__":
    raise SystemExit(main())
