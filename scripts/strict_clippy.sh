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

WORKSPACE_POLICY_SCRIPT="$ACTION_DIR/../../../scripts/workspace_test_policy.py"
if [[ ! -f "$WORKSPACE_POLICY_SCRIPT" ]]; then
    echo "rust-skills2: workspace policy resolver missing at $WORKSPACE_POLICY_SCRIPT" >&2
    exit 2
fi

uv run --no-project python "$SOURCE_POLICY_SCRIPT"

# The reusable gate intentionally owns Clippy configuration. A project-local
# clippy.toml may contain useful developer preferences, but it must not be able
# to weaken the central CI policy (for example by allowing unwrap in consts).
export CLIPPY_CONF_DIR="$ACTION_DIR"
export CARGO_BUILD_WARNINGS=deny

# Clippy reads policy files at compiler execution time. A distributed compiler
# wrapper can execute clippy-driver on a worker that cannot see the action checkout.
# Clear wrappers by default. Trusted self-hosted callers may explicitly preserve a
# wrapper when they guarantee it executes locally in this filesystem namespace.
PRESERVE_RUSTC_WRAPPER="${RUST_SKILLS2_PRESERVE_RUSTC_WRAPPER:-false}"
case "$PRESERVE_RUSTC_WRAPPER" in
    true)
        if [[ -n "${RUST_SKILLS2_RUSTC_WRAPPER:-}" ]]; then
            export RUSTC_WRAPPER="$RUST_SKILLS2_RUSTC_WRAPPER"
        fi
        if [[ -z "${RUSTC_WRAPPER:-}" ]]; then
            echo "rust-skills2: preserve-rustc-wrapper requested but RUSTC_WRAPPER is empty" >&2
            exit 2
        fi
        if [[ -n "${RUST_SKILLS2_SCCACHE_SERVER_PORT:-}" ]]; then
            case "$RUST_SKILLS2_SCCACHE_SERVER_PORT" in
                *[!0-9]*|'')
                    echo "rust-skills2: invalid sccache server port: $RUST_SKILLS2_SCCACHE_SERVER_PORT" >&2
                    exit 2
                    ;;
            esac
            if (( RUST_SKILLS2_SCCACHE_SERVER_PORT < 1 || RUST_SKILLS2_SCCACHE_SERVER_PORT > 65535 )); then
                echo "rust-skills2: sccache server port out of range: $RUST_SKILLS2_SCCACHE_SERVER_PORT" >&2
                exit 2
            fi
            export SCCACHE_SERVER_PORT="$RUST_SKILLS2_SCCACHE_SERVER_PORT"
            export SCCACHE_START_SERVER=0
        fi
        echo "rust-skills2: preserving local compiler wrapper: $RUSTC_WRAPPER"
        [[ -z "${SCCACHE_SERVER_PORT:-}" ]] || echo "rust-skills2: using existing sccache daemon on port $SCCACHE_SERVER_PORT"
        ;;
    false)
        if [[ -n "${RUST_SKILLS2_RUSTC_WRAPPER:-}" || -n "${RUST_SKILLS2_SCCACHE_SERVER_PORT:-}" ]]; then
            echo "rust-skills2: rustc-wrapper/sccache-server-port require preserve-rustc-wrapper=true" >&2
            exit 2
        fi
        export RUSTC_WRAPPER=
        export RUSTC_WORKSPACE_WRAPPER=
        ;;
    *)
        echo "rust-skills2: RUST_SKILLS2_PRESERVE_RUSTC_WRAPPER must be true or false" >&2
        exit 2
        ;;
esac

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
    # #[allow] is forbidden; narrow reasoned #[expect] is the only supported
    # handwritten suppression form for policy-suppressible lints. Keep
    # unreasoned allow attributes fatal in generated/macro-expanded code too.
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

has_cargo_arg() {
    local needle=$1
    local arg
    for arg in "${CARGO_ARGS[@]}"; do
        if [[ "$arg" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

if ! has_cargo_arg --all-targets; then
    run_clippy CARGO_ARGS LINT_ARGS
    exit 0
fi

POLICY_ARGS=(--default-allow-test-panics "$ALLOW_TEST_PANICS")
for arg in "${CARGO_ARGS[@]}"; do
    POLICY_ARGS+=("--cargo-arg=$arg")
done
POLICY_OUTPUT="$(uv run --no-project python "$WORKSPACE_POLICY_SCRIPT" "${POLICY_ARGS[@]}")"

STRICT_PACKAGES=()
RELAXED_PACKAGES=()
while IFS=$'\t' read -r policy package_spec; do
    [[ -z "$policy" ]] && continue
    case "$policy" in
        strict) STRICT_PACKAGES+=("$package_spec") ;;
        relaxed) RELAXED_PACKAGES+=("$package_spec") ;;
        *)
            echo "rust-skills2: invalid workspace policy row: $policy $package_spec" >&2
            exit 2
            ;;
    esac
done <<< "$POLICY_OUTPUT"

if (( ${#STRICT_PACKAGES[@]} == 0 && ${#RELAXED_PACKAGES[@]} == 0 )); then
    echo "rust-skills2: workspace policy resolver returned no selected packages" >&2
    exit 2
fi

if (( ${#RELAXED_PACKAGES[@]} == 0 )); then
    run_clippy CARGO_ARGS LINT_ARGS
    exit 0
fi

PRODUCTION_CARGO_ARGS=()
for arg in "${CARGO_ARGS[@]}"; do
    if [[ "$arg" != "--all-targets" ]]; then
        PRODUCTION_CARGO_ARGS+=("$arg")
    fi
done
run_clippy PRODUCTION_CARGO_ARGS LINT_ARGS

EXAMPLE_CARGO_ARGS=("${PRODUCTION_CARGO_ARGS[@]}" --examples)
run_clippy EXAMPLE_CARGO_ARGS LINT_ARGS

TEST_LINT_ARGS=("${LINT_ARGS[@]}")
TEST_LINT_ARGS+=(
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
    -Aunfulfilled_lint_expectations
    -Aclippy::undocumented_unsafe_blocks
    -Aclippy::missing_safety_doc
    -Dclippy::correctness
    -Dclippy::suspicious
    -Dclippy::perf
    -Dclippy::todo
    -Dclippy::unimplemented
    -Dclippy::dbg_macro
    -Dclippy::await_holding_lock
)

if (( ${#STRICT_PACKAGES[@]} == 0 )); then
    run_clippy CARGO_ARGS TEST_LINT_ARGS
    exit 0
fi

GROUP_BASE_ARGS=()
for ((i = 0; i < ${#CARGO_ARGS[@]}; i++)); do
    arg="${CARGO_ARGS[$i]}"
    case "$arg" in
        --workspace|--all-targets|--lib|--bins|--examples|--tests|--benches)
            ;;
        -p|--package|--exclude|--bin|--example|--test|--bench)
            ((i += 1))
            ;;
        --package=*|--exclude=*|--bin=*|--example=*|--test=*|--bench=*)
            ;;
        *)
            GROUP_BASE_ARGS+=("$arg")
            ;;
    esac
done

STRICT_TEST_CARGO_ARGS=("${GROUP_BASE_ARGS[@]}")
for package_spec in "${STRICT_PACKAGES[@]}"; do
    STRICT_TEST_CARGO_ARGS+=(--package "$package_spec")
done
STRICT_TEST_CARGO_ARGS+=(--tests --benches)
run_clippy STRICT_TEST_CARGO_ARGS LINT_ARGS

RELAXED_TEST_CARGO_ARGS=("${GROUP_BASE_ARGS[@]}")
for package_spec in "${RELAXED_PACKAGES[@]}"; do
    RELAXED_TEST_CARGO_ARGS+=(--package "$package_spec")
done
RELAXED_TEST_CARGO_ARGS+=(--tests --benches)
run_clippy RELAXED_TEST_CARGO_ARGS TEST_LINT_ARGS
