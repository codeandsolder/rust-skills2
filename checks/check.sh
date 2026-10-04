#!/usr/bin/env bash
# One command that reproduces CI locally. Run from anywhere:
#
#     bash checks/check.sh
#
# Toolchain/target are pinned by checks/rust-toolchain.toml (Rust 1.99.0) and
# x86_64-unknown-linux-gnu. `cargo check` type-checks without linking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="x86_64-unknown-linux-gnu"
UV="${UV:-uv}"

# Rule validation must be reproducible even when the developer's Cargo config
# points at a distributed compiler wrapper whose worker cannot see this
# generated-example tree.
export RUSTC_WRAPPER=
export RUSTC_WORKSPACE_WRAPPER=

run_python() {
    "$UV" run --no-project python "$@"
}

echo "==> structure, links, and index parity"
run_python "$ROOT/checks/validate.py"
run_python "$ROOT/checks/gen_index.py" --check

echo "==> verifier metadata regression tests"
run_python "$ROOT/checks/test_gen_metadata.py"

echo "==> maintenance renderer regression tests"
run_python "$ROOT/checks/test_maintenance_renderer.py"

echo "==> generating example files from rules"
cd "$ROOT/checks"
run_python gen.py
run_python check_contract_inventory.py

echo "==> compile-checking ordinary examples (target: $TARGET)"
cargo check --examples --target "$TARGET" --keep-going --message-format=json \
    > check.json 2> check.err || true

echo "==> enforcing expectations and legacy baseline"
run_python analyze.py check.json \
    --check-baseline baseline.txt \
    --good-exceptions good-exceptions.txt

echo "==> fixture-backed contracts"
run_python run_fixture_contracts.py "$TARGET"

echo "All checks passed."
