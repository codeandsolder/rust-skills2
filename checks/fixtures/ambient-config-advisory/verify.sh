#!/usr/bin/env bash
set -euo pipefail
ROOT="${RUST_SKILLS_ROOT:?RUST_SKILLS_ROOT is required}"
TARGET="${RUST_SKILLS_TARGET:?RUST_SKILLS_TARGET is required}"
FIXTURE="$ROOT/checks/fixtures/ambient-config-advisory"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/checks/target}/ambient-config-advisory"

# No execution of the fixture: the compiler resolves each actual Rust path.
# Do not bypass or replace the caller's managed compiler wrapper.
bash "$ROOT/scripts/audit_ambient_config.sh" \
    --manifest-path "$FIXTURE/Cargo.toml" --locked --target "$TARGET" \
    --target-dir "$TARGET_DIR" --message-format=json |
    uv run --no-project python "$FIXTURE/verify.py" "$FIXTURE/src/lib.rs"
