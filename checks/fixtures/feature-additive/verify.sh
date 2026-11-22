#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?root required}"
TARGET="${2:?target required}"
MANIFEST="$ROOT/checks/fixtures/feature-additive/Cargo.toml"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/checks/target}/feature-additive"

CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    --lib \
    --target "$TARGET" \
    --locked \
    --quiet

CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    --lib \
    --target "$TARGET" \
    --no-default-features \
    --locked \
    --quiet
