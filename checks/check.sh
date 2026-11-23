#!/usr/bin/env bash
# One command that reproduces CI locally. Run from anywhere:
#
#     bash checks/check.sh ../ci-workflows/zipp-python/run.mjs
#
# Toolchain/target are pinned by rust-toolchain.toml and
# x86_64-unknown-linux-gnu. `cargo check` type-checks without linking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="x86_64-unknown-linux-gnu"
ZIPP_RUNNER="$(realpath "${1:?usage: bash checks/check.sh ZIPP_RUNNER}")"

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

echo "==> native Rust rule tooling and regression tests"
TOOLS_TARGET="${CARGO_TARGET_DIR:-$ROOT/checks/target}"
cargo test --locked --manifest-path "$ROOT/checks/ci-tool/Cargo.toml" --target-dir "$TOOLS_TARGET"
cargo build --locked --manifest-path "$ROOT/checks/ci-tool/Cargo.toml" --target-dir "$TOOLS_TARGET"
CI_TOOL="$TOOLS_TARGET/debug/rust-skills-ci"
"$CI_TOOL" "$ROOT" validate
"$CI_TOOL" "$ROOT" index --check
"$CI_TOOL" "$ROOT" pins

echo "==> remaining compiler-evidence preparation in Zipp"
node "$ROOT/checks/run_zipp.mjs" "$ZIPP_RUNNER" pre
"$CI_TOOL" "$ROOT" inventory

echo "==> compile-checking ordinary examples (target: $TARGET)"
cd "$ROOT/checks"
cargo check --examples --target "$TARGET" --keep-going --message-format=json > check.json 2> check.err || true

echo "==> enforcing expectations and legacy baseline in Zipp"
node "$ROOT/checks/run_zipp.mjs" "$ZIPP_RUNNER" analyze

echo "==> fixture, example and cancellation runtime contracts"
node "$ROOT/checks/run_contracts.mjs" "$ZIPP_RUNNER" "$TARGET"

echo "All checks passed."
