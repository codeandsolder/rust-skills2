#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/../../target/proc-macro-contracts}"
MANIFEST="$ROOT/Cargo.toml"

CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    -p proc-macro-contract-consumer \
    --target "$TARGET" \
    --quiet

CARGO_TARGET_DIR="$TARGET_DIR" cargo run \
    --manifest-path "$MANIFEST" \
    -p proc-macro-contract-consumer \
    --target "$TARGET" \
    --quiet

set +e
BAD_OUTPUT="$(CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    -p bad-proc-macro-export \
    --target "$TARGET" \
    2>&1)"
BAD_STATUS=$?
set -e

if [[ $BAD_STATUS -eq 0 ]]; then
    echo "FAIL: invalid proc-macro crate unexpectedly compiled" >&2
    exit 1
fi

EXPECTED="cannot export any items other than functions tagged with"
if ! grep -Fq "$EXPECTED" <<<"$BAD_OUTPUT"; then
    echo "FAIL: proc-macro export failed for an unexpected reason" >&2
    echo "$BAD_OUTPUT" >&2
    exit 1
fi

echo "OK: proc-macro workspace, facade re-export, renamed dependency, and export restriction"
