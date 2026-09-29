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

SOURCE_POLICY_SCRIPT="$ACTION_DIR/../../../scripts/check_source_lint_policy.py"
if [[ ! -f "$SOURCE_POLICY_SCRIPT" ]]; then
    echo "rust-skills2: source policy checker missing at $SOURCE_POLICY_SCRIPT" >&2
    exit 2
fi

uv run --no-project python "$SOURCE_POLICY_SCRIPT"

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
export RUSTC_WORKSPACE_WRAPPER=

read -r -a CARGO_ARGS <<< "${RUST_SKILLS2_CARGO_ARGS:---locked --workspace --all-targets}"

# Everything is deny-level at compiler/Clippy level. Proc macros legitimately
# inject internal allow attributes, so command-line forbid is not composable
# even for concrete lints (for example Leptos/TypedBuilder allows clippy::panic).
# The source-policy pass above makes selected lints unsuppressible in handwritten
# source while still allowing macro-generated code to manage its own internals.
LINT_ARGS=(
    -Dwarnings

    -Dunfulfilled_lint_expectations
    -Dunexpected_cfgs
    -Dunsafe_op_in_unsafe_fn

    # Proc-macro expansions legitimately inject internal allow attributes.
    # Keep groups fatal at source boundaries while allowing macro internals to
    # lower lint levels where their generated implementation requires it.
    -Dclippy::correctness
    -Dclippy::suspicious
    -Dclippy::perf

    -Dclippy::style
    -Dclippy::complexity
    -Dclippy::pedantic
    -Dclippy::nursery

    -Dclippy::unwrap_used
    -Dclippy::expect_used
    -Dclippy::panic
    -Dclippy::todo
    -Dclippy::unimplemented
    -Dclippy::dbg_macro

    -Dclippy::undocumented_unsafe_blocks
    -Dclippy::missing_safety_doc
    -Dclippy::await_holding_lock

    # Handwritten #[allow] and high-risk #[expect] are rejected by the source
    # policy pass. Generated code may still manage lint levels internally.
    -Dclippy::allow_attributes
    -Dclippy::allow_attributes_without_reason
)

printf 'rust-skills2: cargo +nightly clippy'
printf ' %q' "${CARGO_ARGS[@]}"
printf ' --'
printf ' %q' "${LINT_ARGS[@]}"
printf '\n'

cargo +nightly clippy "${CARGO_ARGS[@]}" -- "${LINT_ARGS[@]}"
