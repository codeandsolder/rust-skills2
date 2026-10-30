#!/usr/bin/env bash
set -euo pipefail

ROOT="${RUST_SKILLS2_REPOSITORY_ROOT:-${GITHUB_WORKSPACE:-$(pwd)}}"
ACTION_DIR="${RUST_SKILLS2_PYTHON_ACTION_DIR:-}"

if [[ -z "$ACTION_DIR" ]]; then
    if [[ -n "${GITHUB_ACTION_PATH:-}" ]]; then
        ACTION_DIR="$GITHUB_ACTION_PATH"
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        ACTION_DIR="$SCRIPT_DIR/../.github/actions/python-strict"
    fi
fi

if [[ ! -f "$ACTION_DIR/ty.toml" ]]; then
    echo "rust-skills2: strict ty config missing at $ACTION_DIR/ty.toml" >&2
    exit 2
fi

cd "$ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "rust-skills2: Python gate requires a Git checkout: $ROOT" >&2
    exit 2
fi

mapfile -d '' PYTHON_FILES < <(git ls-files -z -- '*.py' '*.pyi' '*.pyw')
if (( ${#PYTHON_FILES[@]} == 0 )); then
    echo "rust-skills2: no tracked Python files; Python policy is a no-op"
    exit 0
fi

BAN_PYTHON_OUTSIDE_CI="${RUST_SKILLS2_BAN_PYTHON_OUTSIDE_CI:-true}"
case "$BAN_PYTHON_OUTSIDE_CI" in
    true|false) ;;
    *)
        echo "rust-skills2: RUST_SKILLS2_BAN_PYTHON_OUTSIDE_CI must be true or false" >&2
        exit 2
        ;;
esac

CUSTOM_CI_PREFIXES=()
while IFS= read -r prefix || [[ -n "$prefix" ]]; do
    prefix="${prefix#"${prefix%%[![:space:]]*}"}"
    prefix="${prefix%"${prefix##*[![:space:]]}"}"
    [[ -z "$prefix" ]] && continue
    prefix="${prefix#./}"
    prefix="${prefix%/}"
    case "$prefix" in
        ''|'.'|/*|'..'|../*|*/../*|*/..)
            echo "rust-skills2: invalid python-ci-paths entry: $prefix" >&2
            exit 2
            ;;
    esac
    CUSTOM_CI_PREFIXES+=("$prefix/")
done <<< "${RUST_SKILLS2_PYTHON_CI_PATHS:-}"

is_ci_python_path() {
    local path=$1
    local prefix
    case "$path" in
        .github/*|.gitlab/*|.circleci/*|.buildkite/*|.ci/*|ci/*|scripts/ci/*|tools/ci/*)
            return 0
            ;;
    esac
    for prefix in "${CUSTOM_CI_PREFIXES[@]}"; do
        if [[ "$path" == "$prefix"* ]]; then
            return 0
        fi
    done
    return 1
}

if [[ "$BAN_PYTHON_OUTSIDE_CI" == true ]]; then
    OUTSIDE_CI=()
    for path in "${PYTHON_FILES[@]}"; do
        if ! is_ci_python_path "$path"; then
            OUTSIDE_CI+=("$path")
        fi
    done
    if (( ${#OUTSIDE_CI[@]} > 0 )); then
        echo "rust-skills2: Python is forbidden outside CI-only paths:" >&2
        printf '  %s\n' "${OUTSIDE_CI[@]}" >&2
        echo "rust-skills2: move the files into CI tooling, remove them, or explicitly add a narrow python-ci-paths prefix" >&2
        exit 1
    fi
fi

# ALL is intentionally the starting point. The ignored families are either
# formatter-conflicting, documentation/process policy, highly heuristic security
# checks, or broad style/refactor preferences with routine legitimate exceptions.
# Specific noqa comments remain available; blanket noqa/type-ignore comments are
# rejected by Ruff/ty policy instead of making individual exceptions impossible.
RUFF_IGNORE=(
    D DOC CPY001
    T20 ERA FIX TD
    C90 PLR
    FBT EM TRY PTH SLF N PT TCH ARG S
    INP001 E501
    W191 E111 E114 E117
    Q000 Q001 Q002 Q003 Q004
    COM812 COM819 ISC002
)
RUFF_IGNORE_CSV="$(IFS=,; echo "${RUFF_IGNORE[*]}")"

echo "rust-skills2: Ruff $(uvx --from ruff ruff --version)"
echo "rust-skills2: ty $(uvx --from ty ty --version)"
echo "rust-skills2: checking ${#PYTHON_FILES[@]} tracked Python file(s)"

echo "rust-skills2: ruff check --select ALL --preview"
uvx --from ruff ruff check \
    --preview \
    --select ALL \
    --ignore "$RUFF_IGNORE_CSV" \
    --config 'lint.per-file-ignores = {}' \
    --config 'lint.extend-per-file-ignores = {}' \
    --config 'lint.extend-ignore = []' \
    --config 'lint.allowed-confusables = []' \
    --config 'lint.explicit-preview-rules = false' \
    --config 'lint.flake8-annotations.allow-star-arg-any = false' \
    --config 'lint.flake8-annotations.ignore-fully-untyped = false' \
    --config 'lint.flake8-annotations.mypy-init-return = false' \
    --config 'lint.flake8-annotations.suppress-dummy-args = false' \
    --config 'lint.flake8-annotations.suppress-none-returning = false' \
    --no-force-exclude \
    --no-cache \
    --output-format github \
    "${PYTHON_FILES[@]}"

echo "rust-skills2: ruff format --check"
uvx --from ruff ruff format \
    --check \
    --no-cache \
    --no-force-exclude \
    "${PYTHON_FILES[@]}"

# Type-check each file in the nearest Python project so monorepos and nested
# tooling projects resolve the dependencies that actually belong to them. Each
# distinct project is synced into an ephemeral uv environment; nothing is left
# in the checkout. --locked makes dependency resolution deterministic and fails
# instead of rewriting a stale/missing lockfile. Files outside any Python
# project are still checked, but naturally only resolve their own/stdlib imports.
find_python_project() {
    local path=$1
    local dir
    if [[ "$path" == */* ]]; then
        dir="${path%/*}"
    else
        dir="."
    fi
    while true; do
        if [[ -f "$ROOT/$dir/pyproject.toml" ]]; then
            PYTHON_PROJECT="$dir"
            return 0
        fi
        if [[ "$dir" == "." ]]; then
            PYTHON_PROJECT=""
            return 0
        fi
        if [[ "$dir" == */* ]]; then
            dir="${dir%/*}"
        else
            dir="."
        fi
    done
}

declare -A PROJECT_SET=()
UNPROJECTED_FILES=()
for path in "${PYTHON_FILES[@]}"; do
    find_python_project "$path"
    if [[ -n "$PYTHON_PROJECT" ]]; then
        PROJECT_SET["$PYTHON_PROJECT"]=1
    else
        UNPROJECTED_FILES+=("$path")
    fi
done

TEMP_ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/rust-skills2-python.XXXXXX")"
cleanup_python_envs() {
    rm -rf -- "$TEMP_ROOT"
}
trap cleanup_python_envs EXIT

run_ty() {
    local project=$1
    local python_env=$2
    shift 2
    local -a command=(
        uvx --from ty ty check
        --config-file "$ACTION_DIR/ty.toml"
        --no-force-exclude
        --include-scripts
        --error-on-warning
        --output-format github
    )
    if [[ -n "$project" ]]; then
        command+=(--project "$ROOT/$project" --python "$python_env")
    else
        command+=(--project "$ROOT")
    fi
    command+=("$@")
    printf 'rust-skills2:'
    printf ' %q' "${command[@]}"
    printf '\n'
    "${command[@]}"
}

for project in "${!PROJECT_SET[@]}"; do
    PROJECT_FILES=()
    for path in "${PYTHON_FILES[@]}"; do
        find_python_project "$path"
        if [[ "$PYTHON_PROJECT" == "$project" ]]; then
            PROJECT_FILES+=("$path")
        fi
    done

    env_name="$(printf '%s' "$project" | sha256sum | cut -c1-16)"
    python_env="$TEMP_ROOT/$env_name"
    echo "rust-skills2: syncing Python project $project with uv --locked"
    UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT="$python_env" uv sync \
        --project "$ROOT/$project" \
        --locked \
        --all-groups \
        --all-extras \
        --no-install-project
    run_ty "$project" "$python_env" "${PROJECT_FILES[@]}"
done

if (( ${#UNPROJECTED_FILES[@]} > 0 )); then
    run_ty "" "" "${UNPROJECTED_FILES[@]}"
fi
