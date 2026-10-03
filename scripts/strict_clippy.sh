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

read -r -a CARGO_ARGS <<< "${RUST_SKILLS2_CARGO_ARGS:---locked --workspace --all-targets}"
ALLOW_TEST_PANICS="${RUST_SKILLS2_ALLOW_TEST_PANICS:-false}"
case "$ALLOW_TEST_PANICS" in
    true|false) ;;
    *)
        echo "rust-skills2: RUST_SKILLS2_ALLOW_TEST_PANICS must be true or false" >&2
        exit 2
        ;;
esac

# cargo-args is deliberately a selector surface, not an arbitrary Cargo CLI.
# Fail closed so current or future options cannot mutate the checkout, exit
# successfully without checking, inject rustc flags, or override Cargo policy.
for ((i = 0; i < ${#CARGO_ARGS[@]}; i++)); do
    arg="${CARGO_ARGS[$i]}"
    case "$arg" in
        --locked|--frozen|--offline|--workspace|--all-targets|--all-features|--no-default-features|--lib|--bins|--examples|--tests|--benches|--keep-going|--no-deps)
            ;;
        -p|--package|--exclude|-F|--features|--target|--bin|--example|--test|--bench)
            if ((i + 1 >= ${#CARGO_ARGS[@]})); then
                echo "rust-skills2: cargo-args option requires a value: $arg" >&2
                exit 2
            fi
            ((i += 1))
            value="${CARGO_ARGS[$i]}"
            if [[ -z "$value" || "$value" == -* ]]; then
                echo "rust-skills2: invalid value for cargo-args option $arg: $value" >&2
                exit 2
            fi
            ;;
        --package=*|--exclude=*|--features=*|--target=*|--bin=*|--example=*|--test=*|--bench=*)
            value="${arg#*=}"
            if [[ -z "$value" ]]; then
                echo "rust-skills2: cargo-args option requires a non-empty value: $arg" >&2
                exit 2
            fi
            ;;
        *)
            echo "rust-skills2: unsupported cargo-args option: $arg" >&2
            echo "rust-skills2: cargo-args may select workspace/package/features/target/target-kind and lock/offline behavior only" >&2
            exit 2
            ;;
    esac
done

echo "rust-skills2: cargo +nightly fmt --all --check"
cargo +nightly fmt --all --check

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

    # Handwritten suppressions are validated by the source-policy pass:
    # reasoned, single-lint #[allow] is permitted only for suppressible lints,
    # while broad/high-risk suppressions stay blocked. Keep unreasoned allow
    # attributes fatal, including outside handwritten source.
    -Dclippy::allow_attributes_without_reason
)

run_clippy() {
    local -n cargo_args_ref=$1
    local -n lint_args_ref=$2
    printf 'rust-skills2: cargo +nightly clippy'
    printf ' %q' "${cargo_args_ref[@]}"
    printf ' --'
    printf ' %q' "${lint_args_ref[@]}"
    printf '\n'
    cargo +nightly clippy "${cargo_args_ref[@]}" -- "${lint_args_ref[@]}"
}

if [[ "$ALLOW_TEST_PANICS" == "true" ]] && printf '%s\n' "${CARGO_ARGS[@]}" | grep -qx -- '--all-targets'; then
    # Prove production targets against the full policy before running the
    # all-targets pass with test-only panic ergonomics relaxed.
    PRODUCTION_CARGO_ARGS=()
    for arg in "${CARGO_ARGS[@]}"; do
        if [[ "$arg" != "--all-targets" ]]; then
            PRODUCTION_CARGO_ARGS+=("$arg")
        fi
    done
    PRODUCTION_CARGO_ARGS+=(--lib --bins --examples)
    run_clippy PRODUCTION_CARGO_ARGS LINT_ARGS

    TEST_LINT_ARGS=("${LINT_ARGS[@]}")
    TEST_LINT_ARGS+=(
        # Production targets already passed the uncompromised policy above.
        # In tests/benches, keep correctness/suspicious/perf fatal but do not
        # spend CI effort on style/documentation/ergonomic churn.
        -Aclippy::style
        -Aclippy::complexity
        -Aclippy::pedantic
        -Aclippy::nursery
        -Aclippy::unwrap_used
        -Aclippy::expect_used
        -Aclippy::panic
        -Aclippy::panic_in_result_fn
        -Aclippy::missing_panics_doc
        -Aclippy::assertions_on_constants
    )
    run_clippy CARGO_ARGS TEST_LINT_ARGS
else
    run_clippy CARGO_ARGS LINT_ARGS
fi
