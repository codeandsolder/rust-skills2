#!/usr/bin/env bash
# Run from the target workspace. Forward ordinary Cargo target/feature selectors.
# This deliberately uses a separate Clippy configuration, not the strict gate.
set -euo pipefail
config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/ambient-config" && pwd)"
CLIPPY_CONF_DIR="$config_dir" exec cargo clippy "$@" -- -Wclippy::disallowed_methods
