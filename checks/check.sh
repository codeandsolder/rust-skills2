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

# CI owns compiler caching centrally. Public jobs use runner-local sccache;
# private jobs use Asus's local-only Garage-backed daemon so generated sources
# and policy files remain in the compiler filesystem namespace. Never clear the
# configured wrapper here: doing so silently bypasses the fleet cache invariant.
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    case "${CODEANDSOLDER_SCCACHE_MODE:-}" in
        public-actions|private-local-garage) ;;
        *)
            echo "checks: CI requires canonical sccache setup" >&2
            exit 2
            ;;
    esac
    [[ -n "${RUSTC_WRAPPER:-}" && -n "${SCCACHE_BIN:-}" ]] || {
        echo "checks: canonical CI sccache wrapper is missing" >&2
        exit 2
    }
fi

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

echo "==> compiler evidence and source-policy regression tests"
run_python "$ROOT/checks/test_analyze.py"
run_python "$ROOT/checks/test_source_lint_policy.py"
run_python "$ROOT/checks/test_action_pins.py"
"$UV" run --no-project --with pyyaml python "$ROOT/checks/test_ci_sccache_policy.py"
"$UV" run --no-project --with pyyaml python "$ROOT/scripts/check_ci_sccache_policy.py" --root "$ROOT"

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
