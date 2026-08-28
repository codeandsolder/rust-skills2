#!/usr/bin/env bash
set -euo pipefail

ROOT="${RUST_SKILLS_ROOT:?RUST_SKILLS_ROOT is required}"
TARGET="${RUST_SKILLS_TARGET:?RUST_SKILLS_TARGET is required}"
MANIFEST="$ROOT/checks/fixtures/tokio-special/Cargo.toml"
TARGET_DIR="$ROOT/checks/target/tokio-special"

RUSTFLAGS="--cfg tokio_unstable" CARGO_TARGET_DIR="$TARGET_DIR" cargo check \
    --manifest-path "$MANIFEST" \
    --target "$TARGET" \
    --locked \
    --quiet
