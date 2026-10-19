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
export PYTHONDONTWRITEBYTECODE=1

# Cargo resolves an environment-provided relative target directory from each
# process's current working directory. This script deliberately changes cwd,
# and fixture runners execute from the repository root, so normalize once at
# the caller boundary to keep every build under the same target tree.
if [[ -n "${CARGO_TARGET_DIR:-}" && "$CARGO_TARGET_DIR" != /* ]]; then
    export CARGO_TARGET_DIR="$(pwd -P)/$CARGO_TARGET_DIR"
fi

# Rule validation clears compiler wrappers by default because a distributed worker
# cannot see the generated-example tree. Trusted same-namespace wrappers may be
# preserved explicitly (the self-hosted CI path uses local-only sccache).
if [[ "${RUST_SKILLS2_PRESERVE_RUSTC_WRAPPER:-false}" == "true" ]]; then
    [[ -n "${RUSTC_WRAPPER:-}" ]] || { echo "preserve wrapper requested but RUSTC_WRAPPER is empty" >&2; exit 2; }
else
    export RUSTC_WRAPPER=
    export RUSTC_WORKSPACE_WRAPPER=
fi

run_python() {
    "$UV" run --no-project python "$@"
}

echo "==> structure, links, and index parity"
run_python "$ROOT/checks/validate.py"
run_python "$ROOT/checks/gen_index.py" --check
run_python "$ROOT/checks/gen_review_skill.py" --check

echo "==> verifier metadata regression tests"
run_python "$ROOT/checks/test_gen_metadata.py"

echo "==> maintenance renderer regression tests"
run_python "$ROOT/checks/test_maintenance_renderer.py"

echo "==> compiler evidence and source-policy regression tests"
run_python "$ROOT/checks/test_analyze.py"
run_python "$ROOT/checks/test_source_lint_policy.py"

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

echo "==> cancellation example runtime contracts"
run_python test_async_cancel_safety.py

echo "All checks passed."
