#!/usr/bin/env bash
# One command that reproduces CI locally. Run from anywhere:
#
#     bash checks/check.sh
#
# Toolchain/target are pinned by checks/rust-toolchain.toml (Rust 1.98.0) and
# x86_64-unknown-linux-gnu. `cargo check` type-checks without linking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="x86_64-unknown-linux-gnu"

echo "==> structure, links, and index parity"
python3 "$ROOT/checks/validate.py"
python3 "$ROOT/checks/gen_index.py" --check

echo "==> verifier metadata regression tests"
python3 "$ROOT/checks/test_gen_metadata.py"

echo "==> generating example files from rules"
cd "$ROOT/checks"
python3 gen.py
python3 check_contract_inventory.py

echo "==> compile-checking ordinary examples (target: $TARGET)"
cargo check --examples --target "$TARGET" --keep-going --message-format=json \
    > check.json 2> check.err || true

echo "==> enforcing expectations and legacy baseline"
python3 analyze.py check.json \
    --check-baseline baseline.txt \
    --good-exceptions good-exceptions.txt

echo "==> fixture-backed contracts"
python3 run_fixture_contracts.py "$TARGET"

echo "All checks passed."
