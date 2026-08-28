#!/usr/bin/env bash
set -euo pipefail

ROOT="${RUST_SKILLS_ROOT:?RUST_SKILLS_ROOT is required}"
TARGET="${RUST_SKILLS_TARGET:?RUST_SKILLS_TARGET is required}"
MANIFEST="$ROOT/checks/fixtures/feature-additive/Cargo.toml"
TARGET_DIR="$ROOT/checks/target/feature-additive"

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
