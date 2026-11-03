#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "check_ci_sccache_policy.py"
spec = importlib.util.spec_from_file_location("check_ci_sccache_policy", SCRIPT)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

SHA = "1" * 40
STRICT_SHA = "2" * 40


def inspect(workflow: str, strict_ref: str | None = None) -> list[str]:
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        path = root / ".github/workflows/ci.yml"
        path.parent.mkdir(parents=True)
        path.write_text(workflow)
        return mod.inspect_root(root, strict_ref)


def assert_clean(workflow: str, strict_ref: str | None = None) -> None:
    violations = inspect(workflow, strict_ref)
    assert not violations, violations


def assert_blocked(workflow: str, fragment: str, strict_ref: str | None = None) -> None:
    violations = inspect(workflow, strict_ref)
    assert any(fragment in item for item in violations), violations


assert_clean(
    f"""
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: codeandsolder/ci-workflows/.github/actions/setup-sccache@{SHA}
      - run: cargo test --locked
      - if: always()
        uses: codeandsolder/ci-workflows/.github/actions/finalize-sccache@{SHA}
"""
)
assert_blocked(
    """
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - run: cargo test --locked
""",
    "missing canonical setup-sccache",
)
assert_blocked(
    f"""
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - run: cargo check
      - uses: codeandsolder/ci-workflows/.github/actions/setup-sccache@{SHA}
      - if: always()
        uses: codeandsolder/ci-workflows/.github/actions/finalize-sccache@{SHA}
""",
    "runs after Rust tooling",
)
assert_blocked(
    f"""
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: codeandsolder/ci-workflows/.github/actions/setup-sccache@{SHA}
      - run: cargo test
      - uses: codeandsolder/ci-workflows/.github/actions/finalize-sccache@{SHA}
""",
    "must use if: always()",
)
assert_blocked(
    f"""
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: codeandsolder/ci-workflows/.github/actions/setup-sccache@{SHA}
      - uses: Swatinem/rust-cache@v2
      - run: cargo test
      - if: always()
        uses: codeandsolder/ci-workflows/.github/actions/finalize-sccache@{SHA}
""",
    "Swatinem/rust-cache is forbidden",
)
assert_clean(
    f"""
jobs:
  build:
    uses: codeandsolder/ci-workflows/.github/workflows/rust-sccache.yml@{SHA}
    with:
      command: cargo test
"""
)
assert_clean(
    f"""
jobs:
  strict:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@{STRICT_SHA}
""",
    STRICT_SHA,
)
assert_blocked(
    f"""
jobs:
  strict:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@{'3' * 40}
""",
    "executing gate",
    STRICT_SHA,
)
print("rust-skills2: CI sccache policy regressions passed")
assert_clean(
    """
jobs:
  metadata:
    runs-on: ubuntu-24.04
    steps:
      - uses: dtolnay/rust-toolchain@1111111111111111111111111111111111111111
      - run: |
          cat <<'EOF'
          Review rustc, Cargo, and Clippy changes.
          EOF
"""
)

# Non-compiling Cargo/toolchain operations do not need a compiler cache.
assert_clean(
    """
jobs:
  formatting:
    runs-on: ubuntu-24.04
    steps:
      - run: cargo +nightly fmt --all -- --check
      - run: cargo metadata --format-version 1
      - run: cargo --version
      - run: rustc --version
      - run: cargo package --no-verify
"""
)

# Compiling Cargo commands still require the canonical setup, including unknown
# cargo plugins because they may invoke rustc internally.
for command in (
    "cargo check --locked",
    "cargo +1.99.0 test --workspace",
    "RUSTFLAGS='-D warnings' cargo clippy --all-targets",
    "cargo doc --no-deps",
    "cargo miri test",
    "cargo nextest run",
    "rustc src/main.rs",
):
    assert_blocked(
        f"""
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - run: {command}
""",
        "missing canonical setup-sccache",
    )

# Heredoc documentation must not turn prose/examples into detected compilation.
assert_clean(
    """
jobs:
  docs:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          cat <<'EOF'
          cargo test --workspace
          rustc src/main.rs
          EOF
"""
)

# Legacy cache actions are forbidden even if compilation is hidden behind a task
# runner and therefore cannot be proven from the workflow text alone.
assert_blocked(
    """
jobs:
  hidden-build:
    runs-on: ubuntu-24.04
    steps:
      - uses: Swatinem/rust-cache@v2
      - run: just test-cpu
""",
    "Swatinem/rust-cache is forbidden",
)
