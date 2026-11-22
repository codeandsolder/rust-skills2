#!/usr/bin/env python3
"""Regression test for gen.py expectation metadata parsing."""
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
RULES = ROOT / "rules"
FIXTURE = RULES / "zz_verifier_metadata_fixture.md"
GEN = HERE / "gen.py"
MANIFEST = HERE / "manifest.json"

fixture = r'''# zz-verifier-metadata-fixture

> Temporary generator regression fixture

## Good compile fail

```rust,compile_fail
let _: u8 = "not a byte";
```

## Good ignore

```rust,ignore
this is intentionally not Rust;
```

## Good no run

```rust,no_run
fn compiles_but_is_not_run() {}
```

## Good should panic

```rust,should_panic
fn main() { panic!("runtime behavior is irrelevant to cargo check"); }
```

## Nightly executable

<!-- rust-check: nightly(iter_collect_into); reason=nightly API -->
```rust
#![feature(iter_collect_into)]
fn main() {}
```

## Nightly compile only

<!-- rust-check: nightly(iter_collect_into); reason=nightly API -->
```rust,no_run
#![feature(iter_collect_into)]
fn main() {}
```

## Stable executable

<!-- rust-check: run -->
```rust
fn main() {}
```

## Fixture backed

<!-- rust-check: fixture(feature-additive) -->
```rust
#![cfg_attr(not(feature = "std"), no_std)]
```
'''


def run_gen():
    subprocess.run([sys.executable, str(GEN)], cwd=HERE, check=True)


def main():
    if FIXTURE.exists():
        raise SystemExit(f"refusing to overwrite existing fixture path: {FIXTURE}")
    try:
        FIXTURE.write_text(fixture, encoding="utf-8")
        run_gen()
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        prefix = "zz_verifier_metadata_fixture__"
        rows = [manifest[f"{prefix}{i}"] for i in range(8)]
        got = [(row["expect"], row["generated"]) for row in rows]
        want = [
            ("compile_fail", True),
            ("ignore", False),
            ("compile", True),
            ("compile", True),
            ("nightly", False),
            ("nightly", False),
            ("compile", True),
            ("fixture:feature-additive", False),
        ]
        if got != want:
            raise AssertionError(f"native/fixture expectations: got {got!r}, want {want!r}")
        if [row["nightly_run"] for row in rows[4:6]] != [True, False]:
            raise AssertionError("nightly runtime metadata did not honor no_run")
        for i in (4, 5):
            if not (HERE / "nightly" / "examples" / f"{prefix}{i}.rs").is_file():
                raise AssertionError("nightly source was not generated")
        if not rows[6].get("stable_run") or rows[2].get("stable_run"):
            raise AssertionError("stable runtime metadata did not distinguish compile-only examples")
        print("OK: native rustdoc, runtime, nightly and fixture expectations")
    finally:
        FIXTURE.unlink(missing_ok=True)
        # Restore generated state so the real corpus run that follows sees only
        # repository rules, even when an assertion above fails.
        run_gen()


if __name__ == "__main__":
    main()
