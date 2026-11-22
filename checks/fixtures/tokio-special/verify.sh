#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?root required}"
TARGET="${2:?target required}"
MANIFEST="$ROOT/checks/fixtures/tokio-special/Cargo.toml"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/checks/target}/tokio-special"

RUSTFLAGS="--cfg tokio_unstable" CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    --target "$TARGET" \
    --locked \
    --quiet
