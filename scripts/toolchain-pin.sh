#!/usr/bin/env bash
# Read the repository pin, or validate an explicitly requested candidate.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin=$(sed -nE 's/^channel[[:space:]]*=[[:space:]]*"(nightly-[0-9]{4}-[0-9]{2}-[0-9]{2})"[[:space:]]*$/\1/p' "$root/rust-toolchain.toml")
requested=${1:-$pin}
if [[ ! "$requested" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "expected a dated nightly toolchain, got: $requested" >&2
    exit 2
fi
printf '%s\n' "$requested"
