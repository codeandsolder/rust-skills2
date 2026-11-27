#!/usr/bin/env bash
set -euo pipefail

TOOLCHAIN=$(bash "$(dirname "${BASH_SOURCE[0]}")/toolchain-pin.sh")
PHASE=all
PLAN=
while (( $# )); do
    case "$1" in
        --toolchain|--phase|--plan)
            if (( $# < 2 )); then
                echo "rust-skills2: missing value for $1" >&2
                exit 2
            fi
            case "$1" in
                --toolchain) TOOLCHAIN=$2 ;;
                --phase) PHASE=$2 ;;
                --plan) PLAN=$2 ;;
            esac
            shift 2 ;;
        *)
            echo "usage: strict_clippy.sh [--toolchain nightly-YYYY-MM-DD] [--phase all|format|preflight|compile] [--plan absolute-path]" >&2
            exit 2 ;;
    esac
done
case "$PHASE" in
    all|format)
        [[ -z "$PLAN" ]] || { echo "unexpected plan for $PHASE" >&2; exit 2; } ;;
    preflight|compile)
        [[ "$PLAN" == /* ]] || { echo "split strict phases require an absolute plan path" >&2; exit 2; } ;;
    *) echo "unknown strict phase: $PHASE" >&2; exit 2 ;;
esac
[[ "$TOOLCHAIN" =~ ^nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
    echo "rust-skills2: expected a nightly toolchain" >&2
    exit 2
}

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

if [[ "$PHASE" == all || "$PHASE" == format ]]; then
    echo "rust-skills2: cargo +$TOOLCHAIN fmt --all --check"
    cargo "+$TOOLCHAIN" fmt --all --check
    [[ "$PHASE" != format ]] || exit 0
fi

if [[ "$PHASE" != compile ]]; then
    # Mandatory release-license policy belongs to the strict implementation,
    # not any particular workflow wrapper. Each feature/target selection must
    # validate its own normal dependency graph before compilation.
    LICENSE_POLICY="$ACTION_DIR/../../../scripts/release-licenses.mjs"
    if [[ ! -f "$LICENSE_POLICY" ]]; then
        echo "rust-skills2: release-license policy checker missing at $LICENSE_POLICY" >&2
        exit 2
    fi
    node "$LICENSE_POLICY" "$TOOLCHAIN" "$PWD" "${CARGO_ARGS[*]}"

    SOURCE_POLICY_SCRIPT="$ACTION_DIR/../../../policy-wasm/check.mjs"
    SOURCE_POLICY_MODULE="$ACTION_DIR/../../../policy-wasm/module.json"
    if [[ ! -f "$SOURCE_POLICY_SCRIPT" || ! -f "$SOURCE_POLICY_MODULE" ]]; then
        echo "rust-skills2: source policy checker missing at $SOURCE_POLICY_SCRIPT" >&2
        exit 2
    fi

    if has_cargo_arg --all-targets; then
        POLICY_OUTPUT="$(node "$SOURCE_POLICY_SCRIPT" "$SOURCE_POLICY_MODULE" "$TOOLCHAIN" "$ALLOW_TEST_PANICS" "${CARGO_ARGS[@]}")"
    else
        node "$SOURCE_POLICY_SCRIPT" "$SOURCE_POLICY_MODULE" "$TOOLCHAIN"
    fi

    if [[ "$PHASE" == preflight ]]; then
        # The provider allocates one private runner-local plan per exact scope.
        # Publish only after every mandatory source/license check has succeeded.
        (
            umask 077
            printf '%s\n' "$TOOLCHAIN" "$PWD" "$ALLOW_TEST_PANICS" "${CARGO_ARGS[*]}" "${POLICY_OUTPUT:-}" > "$PLAN"
        )
        exit 0
    fi
else
    {
        IFS= read -r plan_toolchain
        IFS= read -r plan_directory
        IFS= read -r plan_panics
        IFS= read -r plan_selectors
        if [[ "$plan_toolchain" != "$TOOLCHAIN" || "$plan_directory" != "$PWD" ||
            "$plan_panics" != "$ALLOW_TEST_PANICS" || "$plan_selectors" != "${CARGO_ARGS[*]}" ]]; then
            echo "rust-skills2: strict plan does not match the compilation scope" >&2
            exit 2
        fi
        POLICY_OUTPUT=$(cat)
    } < "$PLAN"
fi

# The reusable gate intentionally owns Clippy configuration. A project-local
# clippy.toml may contain useful developer preferences, but it must not be able
# to weaken the central CI policy (for example by allowing unwrap in consts).
export CLIPPY_CONF_DIR="$ACTION_DIR"
export CARGO_BUILD_WARNINGS=deny

# CI compilation is required to run through the centrally configured sccache.
# The private strict-CI backend is intentionally local-only so clippy-driver can
# read this checked-out policy directory; public runners use runner-local sccache.
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    case "${CODEANDSOLDER_SCCACHE_MODE:-}" in
        public-actions|private-local-garage) ;;
        *)
            echo "rust-skills2: CI requires canonical sccache setup; invalid/missing CODEANDSOLDER_SCCACHE_MODE=${CODEANDSOLDER_SCCACHE_MODE:-<unset>}" >&2
            exit 2
            ;;
    esac
    if [[ -z "${RUSTC_WRAPPER:-}" || -z "${SCCACHE_BIN:-}" ]]; then
        echo "rust-skills2: CI requires RUSTC_WRAPPER and SCCACHE_BIN from canonical sccache setup" >&2
        exit 2
    fi
    if [[ -n "${RUSTC_WORKSPACE_WRAPPER:-}" ]]; then
        echo "rust-skills2: RUSTC_WORKSPACE_WRAPPER may not override the canonical CI compiler cache" >&2
        exit 2
    fi
    "$SCCACHE_BIN" --version
    echo "rust-skills2: mandatory CI sccache mode: $CODEANDSOLDER_SCCACHE_MODE"
fi

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
    -Dclippy::deprecated_attributes_without_note
    -Dclippy::must_use_without_reason
)

run_clippy() {
    local -n cargo_args_ref=$1
    local -n lint_args_ref=$2
    printf 'rust-skills2: cargo +%s clippy' "$TOOLCHAIN"
    printf ' %q' "${cargo_args_ref[@]}"
    printf ' --'
    printf ' %q' "${lint_args_ref[@]}"
    printf '\n'
    cargo "+$TOOLCHAIN" clippy "${cargo_args_ref[@]}" -- "${lint_args_ref[@]}"
}

if ! has_cargo_arg --all-targets; then
    run_clippy CARGO_ARGS LINT_ARGS
    exit 0
fi

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

# ShellCheck cannot see the local -n variable reference inside run_clippy.
# shellcheck disable=SC2034
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
