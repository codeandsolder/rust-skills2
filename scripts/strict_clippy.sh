#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
WORKDIR="${RUST_SKILLS2_WORKING_DIRECTORY:-.}"
ACTION_DIR="${RUST_SKILLS2_ACTION_DIR:-}"

if [[ -z "$ACTION_DIR" ]]; then
    # When called by the composite action, GITHUB_ACTION_PATH points at
    # .github/actions/rust-strict. For repository-local self-tests, derive it
    # from this script instead.
    if [[ -n "${GITHUB_ACTION_PATH:-}" ]]; then
        ACTION_DIR="$GITHUB_ACTION_PATH"
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        ACTION_DIR="$SCRIPT_DIR/../.github/actions/rust-strict"
    fi
fi

if [[ ! -f "$ACTION_DIR/clippy.toml" ]]; then
    echo "rust-skills2: strict Clippy config missing at $ACTION_DIR/clippy.toml" >&2
    exit 2
fi

cd "$ROOT/$WORKDIR"

if [[ ! -f Cargo.toml ]]; then
    echo "rust-skills2: no Cargo.toml in $PWD" >&2
    exit 2
fi

# The reusable gate intentionally owns Clippy configuration. A project-local
# clippy.toml may contain useful developer preferences, but it must not be able
# to weaken the central CI policy (for example by allowing unwrap in consts).
export CLIPPY_CONF_DIR="$ACTION_DIR"
export CARGO_BUILD_WARNINGS=deny

# Clippy reads policy files at compiler execution time. A distributed RUSTC_WRAPPER
# can execute clippy-driver on a worker that cannot see the action checkout, making
# CLIPPY_CONF_DIR either fail or silently diverge. Keep the policy pass local and
# deterministic. Target caches still make repeated CI runs cheap.
export RUSTC_WRAPPER=

read -r -a CARGO_ARGS <<< "${RUST_SKILLS2_CARGO_ARGS:---locked --workspace --all-targets}"

# High-confidence categories use `forbid`: source-level #[allow] and #[expect]
# cannot suppress them. Opinionated/churn-prone groups remain `deny`: they
# still fail CI, but a narrowly-scoped #[expect(..., reason = "...")] can be
# used when nightly Clippy has a genuine false positive or generated-code issue.
LINT_ARGS=(
    -Dwarnings

    -Funfulfilled_lint_expectations
    -Funexpected_cfgs
    -Funsafe_op_in_unsafe_fn

    -Fclippy::correctness
    -Fclippy::suspicious
    -Fclippy::perf

    -Dclippy::style
    -Dclippy::complexity
    -Dclippy::pedantic
    -Dclippy::nursery

    -Fclippy::unwrap_used
    -Fclippy::expect_used
    -Fclippy::panic
    -Fclippy::todo
    -Fclippy::unimplemented
    -Fclippy::dbg_macro

    -Fclippy::undocumented_unsafe_blocks
    -Fclippy::missing_safety_doc
    -Fclippy::await_holding_lock

    # Ordinary outer #[allow(...)] is not accepted. For suppressible lints use
    # a precise #[expect(..., reason = "...")]; forbidden lints cannot be
    # expected because their level cannot be lowered.
    -Fclippy::allow_attributes
    -Dclippy::allow_attributes_without_reason
)

printf 'rust-skills2: cargo +nightly clippy'
printf ' %q' "${CARGO_ARGS[@]}"
printf ' --'
printf ' %q' "${LINT_ARGS[@]}"
printf '\n'

cargo +nightly clippy "${CARGO_ARGS[@]}" -- "${LINT_ARGS[@]}"
