#!/usr/bin/env bash
# Temporary, shared-checkout lint campaigns. Normal CI remains unchanged.
# shellcheck disable=SC2030,SC2031 # Build environment is deliberately scoped to subshells.
set -euo pipefail
SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { printf 'lint-campaign: %s\n' "$*" >&2; exit 1; }
say() { printf 'lint-campaign: %s\n' "$*" >&2; }
usage() {
    cat <<'HELP'
Usage:
  lint_campaign.sh init STATE TARGET WORKTREE_ROOT [SMOKE_COMMAND]
  lint_campaign.sh init-issues STATE TARGET WORKTREE_ROOT MANIFEST [SMOKE_COMMAND]
  lint_campaign.sh claim-issue STATE WORKER [ISSUE_ID]
  lint_campaign.sh issues STATE
  lint_campaign.sh amend-issues STATE MANIFEST
  lint_campaign.sh refresh STATE
  lint_campaign.sh status STATE
  lint_campaign.sh claim STATE WORKER [LINT_BUDGET=20] [PATH_PREFIX] [MAX_FILES=4]
  lint_campaign.sh extend STATE WORKER FILE...
  lint_campaign.sh checkpoint STATE WORKER
  lint_campaign.sh publish STATE WORKER [FOCUSED_TEST_COMMAND]  # enqueue only
  lint_campaign.sh serve STATE                                # one validator
  lint_campaign.sh drain STATE                                # drain once
  lint_campaign.sh results STATE [WORKER]
  lint_campaign.sh recover STATE JOB WORKER
  lint_campaign.sh upgrade STATE [RUSTUP_HOME]
  lint_campaign.sh release STATE WORKER
  lint_campaign.sh defer STATE WORKER REASON
  lint_campaign.sh retry STATE FILE...
  lint_campaign.sh finish STATE [FINAL_TEST_COMMAND]
  lint_campaign.sh stop STATE

STATE and WORKTREE_ROOT must be absolute, outside repository worktrees.
init runs inside the target Git repository. All workers use the same local
Git common directory and STATE. Remote is origin; TARGET is an existing
temporary topic branch, not main/master. Require the managed RUSTC_WRAPPER.
LINT_CAMPAIGN_NIGHTLY (default nightly) and LINT_CAMPAIGN_STABLE (stable)
are fixed at init, including actual rustc versions.
Set LINT_CAMPAIGN_RUSTUP_HOME to an isolated Rustup home to persist the
compiler installation for every worker and validator. An active campaign
can adopt an isolated home with upgrade, only if its compiler versions match.
Cargo compilation concurrency defaults to 32 and is clamped to at least 16.
HELP
}
[[ $# -ge 1 ]] || { usage; exit 2; }
action=$1; shift
if [[ "$action" == help || "$action" == --help ]]; then usage; exit 0; fi
[[ $# -ge 1 ]] || die "STATE required"
state=$1; shift
[[ "$state" == /* ]] || die "STATE must be absolute"
# Do not let the caller accidentally create logs/targets inside the target tree.
outside() {
    local candidate=$1 root=$2
    [[ "$candidate" != "$root" && "$candidate/" != "$root/"* ]]
}
valid_worker() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}$ ]] || die "invalid worker id: $1"; }
valid_repo_path() {
    [[ -n "$1" && "$1" != */ && "$1" != /* && "$1" != -* && "$1" != *$'\n'* &&
       "$1" != *$'\r'* && "$1" != *$'\t'* && "/$1/" != *'/../'* &&
       "/$1/" != *'/./'* && "$1" != *'//'* && "$1" != .git && "$1" != .git/* ]] ||
       die "claim only safe repository-relative file paths: $1"
}
valid_file() {
    valid_repo_path "$1"
    [[ -f "$state/issues.json" || "$1" == *.rs ]] || die "lint claims may only contain Rust files"
}
git_repo() { git -C "$repo" "$@"; }
git_work() { git -C "$work" "$@"; }
# A serial validation queue must still feed the distributed compiler pool.
# Clamp inherited settings (including CI/service defaults) before any build.
configure_build_jobs() {
    local jobs="${CARGO_BUILD_JOBS:-32}"
    [[ "$jobs" =~ ^[1-9][0-9]{0,8}$ ]] || die "CARGO_BUILD_JOBS must be a positive integer"
    if ((jobs < 16)); then
        say "raising CARGO_BUILD_JOBS from $jobs to minimum 16"
        jobs=16
    fi
    export CARGO_BUILD_JOBS="$jobs"
}
need_cache() {
    configure_build_jobs
    [[ -n "${RUSTC_WRAPPER:-}" ]] || die "set the existing managed RUSTC_WRAPPER; no cache bypass"
    [[ -z "${RUSTC_WORKSPACE_WRAPPER:-}" ]] || die "unexpected workspace compiler wrapper"
    [[ -z "${RUSTFLAGS:-}${CARGO_ENCODED_RUSTFLAGS:-}${CARGO_BUILD_RUSTFLAGS:-}${CARGO_BUILD_WARNINGS:-}" ]] ||
        die "unset external rustflags/build-warning overrides for comparable inventories"
}
# A single registry protects claims even if two campaigns are initialized from
# different worktrees of the same repository. No lock is held during builds.
lock_claims() { exec {claims_fd}>"$state/claims.lock"; flock -x "$claims_fd"; }
unlock_claims() { flock -u "$claims_fd"; exec {claims_fd}>&-; }
lock_worker() {
    valid_worker "$worker"
    exec {worker_fd}>"$state/locks/$worker.lock"
    flock -n "$worker_fd" || die "worker $worker already has a running command"
}
clean_at() {
    local status
    status=$(git -C "$1" status --porcelain --untracked-files=all) || die "cannot inspect $1"
    [[ -z "$status" ]] || die "worktree has uncommitted files: $1"
}
clean_policy() {
    local status
    status=$(git -C "$SKILLS" status --porcelain --untracked-files=all -- \
        scripts/lint_campaign.sh scripts/lint_campaign_queue.sh scripts/lint_campaign_issues.sh scripts/strict_clippy.sh scripts/check_source_lint_policy.py \
        scripts/workspace_test_policy.py .github/actions/rust-strict) || die "cannot inspect policy checkout"
    [[ -z "$status" ]] || die "campaign tool or policy files have uncommitted edits"
}
use_campaign_rustup() {
    if [[ -n "$rustup_home" ]]; then
        [[ "$rustup_home" == /* && -d "$rustup_home/toolchains" ]] ||
            die "campaign Rustup home missing or invalid: $rustup_home"
        export RUSTUP_HOME="$rustup_home"
    fi
}
check_compilers() {
    [[ "$(rustc "+$nightly" --version)" == "$nightly_version" &&
       "$(rustc +nightly --version)" == "$nightly_version" ]] ||
        die "nightly compiler drift; start a new campaign"
    [[ "$(rustc "+$stable" --version)" == "$stable_version" ]] ||
        die "stable compiler drift; start a new campaign"
    if [[ -n "$rustup_home" ]]; then
        [[ "$(rustc +stable --version)" == "$stable_version" ]] ||
            die "stable alias differs from pinned compiler"
    fi
}
check_tools() {
    need_cache
    check_compilers
    [[ "$(git -C "$SKILLS" rev-parse HEAD)" == "$skills_revision" ]] ||
        die "rust-skills2 revision changed; use the original checkout"
    clean_policy
}
remote_tip() {
    # Isolate fetch of the target ref; do not touch the checked-out local branch.
    local tip attempt
    # Worktree pushes and fetches share the tracking ref. A short retry
    # tolerates a competing successful fast-forward without hiding failures.
    for attempt in 1 2 3; do
        if git_repo fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$target:refs/remotes/origin/$target"; then
            break
        fi
        [[ "$attempt" != 3 ]] || die "target fetch failed"
        sleep 1
    done
    tip=$(git_repo rev-parse "refs/remotes/origin/$target") || die "target ref missing"
    git_repo merge-base --is-ancestor "$base" "$tip" ||
        die "campaign target no longer descends from its initial revision"
    printf '%s\n' "$tip"
}
# Inventory runs with style lints as warnings so Cargo can reach every target.
# Actual compiler failures and safety diagnostics remain fatal, and publishing
# also runs the stable, source-policy and configured regression gates.
inventory() {
    local checkout=$1 revision=$2 dir=$3 out="$state/inventory/$2.json"
    local inv_fd snapshot
    exec {inv_fd}>"$state/locks/inventory-$revision.lock"
    flock -x "$inv_fd"
    if [[ ! -f "$out" ]]; then
        clean_at "$checkout"
        [[ "$(git -C "$checkout" rev-parse HEAD)" == "$revision" ]] || die "inventory checkout moved"
        mkdir -p "$dir"
        say "inventory $revision"
        (
            cd "$checkout" || exit
            export CARGO_TARGET_DIR="$dir/target" CARGO_INCREMENTAL=0
            export GITHUB_WORKSPACE="$checkout" RUST_SKILLS2_WORKING_DIRECTORY=.
            export RUST_SKILLS2_ACTION_DIR="$SKILLS/.github/actions/rust-strict"
            export RUST_SKILLS2_CARGO_ARGS="--locked --workspace --all-targets"
            export RUST_SKILLS2_ALLOW_TEST_PANICS="$allow_test_panics"
            bash "$SKILLS/scripts/strict_clippy.sh" --inventory
        ) >"$state/logs/$revision.clippy.jsonl" 2>"$state/logs/$revision.clippy.stderr" ||
            die "inventory failed; see $state/logs/$revision.clippy.stderr and .jsonl"
        clean_at "$checkout"
        [[ "$(git -C "$checkout" rev-parse HEAD)" == "$revision" ]] || die "inventory checkout moved"
        snapshot=$(mktemp "$state/inventory/.snapshot.XXXXXX")
        jq -se --arg root "$checkout/" '
          def normalize_path:
            (if startswith($root) then ltrimstr($root) else . end) |
            if startswith("/") then . else
              reduce (split("/")[]) as $part ([];
                if $part=="" or $part=="." then .
                elif $part==".." and length>0 and .[-1]!=".." then .[0:-1]
                else .+[$part] end) | join("/")
            end;
          if ([.[] | select(.reason == "build-finished")] | length > 0 and all(.[]; .success == true)) then
            [.[] | select(.reason == "compiler-message") | .message as $m |
              select($m.level == "warning") |
              ([ $m.spans[]? | select(.is_primary) ] |
               if length == 0 then [{file_name:"<unlocated>",line_start:0,column_start:0}]
               else . end)[] |
              {file:(.file_name | normalize_path),
               line:.line_start, column:.column_start,
               code:($m.code.code // "<uncoded>"), message:$m.message}]
            | unique_by([.file,.line,.column,.code,.message])
          else error("Cargo did not report successful completion") end
        ' "$state/logs/$revision.clippy.jsonl" >"$snapshot" ||
            { rm -f -- "$snapshot"; die "invalid Cargo inventory"; }
        mv -- "$snapshot" "$out"
    fi
    flock -u "$inv_fd"; exec {inv_fd}>&-
}
inventory_tip() {
    local revision=$1 temporary build
    if [[ -f "$state/inventory/$revision.json" ]]; then return; fi
    # Other workers can simultaneously validate their own revision. Disposable
    # detached checkout and build directory are owned solely by this invocation.
    temporary=$(mktemp -d "$workroot/.inventory.XXXXXX")
    build=$(mktemp -d "$state/build/inventory.XXXXXX")
    (
        trap 'git_repo worktree remove "$temporary" >/dev/null 2>&1 || true; rmdir "$temporary" 2>/dev/null || true; rm -rf -- "$build"' EXIT
        git_repo worktree add --quiet --detach "$temporary" "$revision"
        inventory "$temporary" "$revision" "$build"
    )
}
load_worker() {
    worker=$1; lock_worker
    claim="$state/claims/$worker.json"
    [[ -f "$claim" ]] || die "no active claim for $worker"
    work=$(jq -er .worktree "$claim")
    topic=$(jq -er .branch "$claim")
    [[ "$(git_work symbolic-ref --short HEAD)" == "$topic" ]] || die "incorrect worker branch"
}
scope_diff() {
    local tip=$1 revision=$2 changed
    changed=$(git_work diff --no-renames --name-only -z "$tip" "$revision" |
        jq -Rs 'split("\u0000") | map(select(length>0))')
    jq -ne --argjson changed "$changed" --slurpfile c "$claim" '
      ($changed - $c[0].files) as $outside |
      if ($changed|length)==0 then error("empty change")
      elif ($outside|length)>0 then error("out of scope: "+($outside|join(", ")))
      else true end' >/dev/null || die "claim scope check failed"
}
compare_inventory() {
    local before=$1 after=$2
    if [[ -f "$state/issues.json" ]]; then
        [[ "$(jq length "$state/inventory/$before.json")" == 0 &&
           "$(jq length "$state/inventory/$after.json")" == 0 ]] ||
            die "issue campaign must preserve clean strict inventory"
        return
    fi
    jq -ne --slurpfile old "$state/inventory/$before.json" \
           --slurpfile new "$state/inventory/$after.json" --slurpfile c "$claim" '
      def owned($paths): .file as $f | ($paths | index($f)) != null;
      def buckets: group_by([.file,.code,.message]) |
          map({key:([.[0].file,.[0].code,.[0].message]|tojson), value:length}) | from_entries;
      $c[0].files as $paths |
      ($old[0] | map(select(owned($paths))) | length) as $n_before |
      ($new[0] | map(select(owned($paths))) | length) as $n_after |
      ($old[0] | map(select(owned($paths)|not)) | buckets) as $outside_before |
      ($new[0] | map(select(owned($paths)|not)) | buckets) as $outside_after |
      [$outside_after | to_entries[] | select(.value > ($outside_before[.key] // 0))] as $regressions |
      def owned_codes: map(select(owned($paths))) | group_by([.file,.code]) |
          map({key:([.[0].file,.[0].code]|tojson),value:length}) | from_entries;
      ($old[0]|owned_codes) as $old_codes |
      ($new[0]|owned_codes) as $new_codes |
      [$new_codes|to_entries[]|select(.value>($old_codes[.key]//0))] as $owned_increases |
      {owned_before:$n_before, owned_after:$n_after, outside_increases:$regressions,
       owned_category_increases:$owned_increases} |
      if $n_after >= $n_before or ($regressions|length)>0 or ($owned_increases|length)>0 then
        error(tojson) else . end
    ' || die "lint progress/regression check failed"
}
validate() {
    local revision=$1 dir="$state/build/validator"
    clean_at "$work"
    (
        cd "$work" || exit
        export CARGO_TARGET_DIR="$dir/target" CARGO_INCREMENTAL=0
        cargo "+$stable" fmt --all -- --check || exit
        cargo "+$stable" clippy --workspace --all-targets --locked -- -D warnings || exit
        uv run --no-project python "$SKILLS/scripts/check_source_lint_policy.py" || exit
        printf 'Shared smoke command: %s\n' "$smoke"
        bash -euo pipefail -c "$smoke" || exit
        printf 'Worker focused command: %s\n' "$focused"
        bash -euo pipefail -c "$focused"
    ) >"$state/logs/$revision.gate.log" 2>&1 ||
        die "regression gate failed; see $state/logs/$revision.gate.log"
    clean_at "$work"
    [[ "$(git_work rev-parse HEAD)" == "$revision" ]] || die "worker changed during checks"
}
remove_claim() {
    local tip=$1 revision checkpoint_ref remote_checkpoint reason=${2:-} file blob key
    revision=$(git_work rev-parse HEAD)
    clean_at "$work"
    git_repo merge-base --is-ancestor "$revision" "$tip" ||
        die "not published; preserve the worktree or checkpoint first"
    checkpoint_ref="refs/heads/$topic"
    remote_checkpoint=$(git_repo ls-remote --heads origin "$checkpoint_ref") || die "cannot inspect remote checkpoint"
    if [[ -n "$remote_checkpoint" ]]; then
        remote_checkpoint=${remote_checkpoint%%$'\t'*}
        git_repo merge-base --is-ancestor "$remote_checkpoint" "$tip" || die "remote checkpoint has unpublished work"
        git_repo push --force-with-lease="$checkpoint_ref:$remote_checkpoint" origin ":$checkpoint_ref"
    fi
    # Keep the claim until its worktree has successfully been removed.
    lock_claims
    if [[ -n "$reason" ]]; then
        while IFS= read -r file; do
            if ! blob=$(git_repo rev-parse "$tip:$file" 2>/dev/null); then continue; fi
            key=$(printf '%s' "$file" | git hash-object --stdin)
            jq -n --arg file "$file" --arg blob "$blob" --arg reason "$reason" --arg tip "$tip" \
                '{file:$file,blob:$blob,reason:$reason,revision:$tip}' >"$state/deferred/$key.tmp"
            mv -- "$state/deferred/$key.tmp" "$state/deferred/$key.json"
        done < <(jq -r '.files[]' "$claim")
    fi
    git_repo worktree remove "$work"
    git_repo update-ref -d "refs/heads/$topic" "$revision"
    rm -- "$claim"
    rm -rf -- "$state/build/$worker"
    unlock_claims
}
# shellcheck source=scripts/lint_campaign_queue.sh
source "$SKILLS/scripts/lint_campaign_queue.sh"
# shellcheck source=scripts/lint_campaign_issues.sh
source "$SKILLS/scripts/lint_campaign_issues.sh"
if [[ "$action" == init || "$action" == init-issues ]]; then
    manifest=''
    if [[ "$action" == init-issues ]]; then
        [[ $# -ge 3 && $# -le 4 ]] || die "init-issues requires TARGET WORKTREE_ROOT MANIFEST [SMOKE_COMMAND]"
        manifest=$(realpath -e "$3")
        validate_issue_manifest "$manifest"
        set -- "$1" "$2" "${4:-cargo +stable test --workspace --locked}"
    fi
    [[ $# -ge 2 && $# -le 3 ]] || die "init requires TARGET WORKTREE_ROOT [SMOKE_COMMAND]"
    target=$1; workroot=$2; smoke=${3:-cargo +stable test --workspace --locked}
    repo=$(git rev-parse --show-toplevel)
    repo=$(realpath "$repo")
    [[ "$target" != main && "$target" != master && "$target" != HEAD ]] ||
        die "use a temporary integration/topic branch"
    git check-ref-format "refs/heads/$target" >/dev/null || die "invalid target branch"
    default_ref=$(git_repo ls-remote --symref origin HEAD) || die "cannot inspect remote default"
    if [[ "$default_ref" == "ref: refs/heads/$target"$'\t'HEAD* ]]; then
        die "use a temporary integration/topic branch, not the remote default"
    fi
    [[ "$workroot" == /* ]] || die "WORKTREE_ROOT must be absolute"
    state=$(realpath -m "$state"); workroot=$(realpath -m "$workroot")
    if ! outside "$state" "$repo" || ! outside "$workroot" "$repo" || ! outside "$workroot" "$state" ||
        ! outside "$state" "$workroot"; then
        die "state and worktrees need separate external directories"
    fi
    # Check every existing worktree, not merely the checkout invoking init.
    while IFS= read -r path; do
        if ! outside "$state" "$path" || ! outside "$workroot" "$path"; then
            die "state/worktree root overlaps existing worktree: $path"
        fi
    done < <(git_repo worktree list --porcelain | sed -n 's/^worktree //p')
    need_cache
    nightly=${LINT_CAMPAIGN_NIGHTLY:-nightly}
    stable=${LINT_CAMPAIGN_STABLE:-stable}
    rustup_home=${LINT_CAMPAIGN_RUSTUP_HOME:-}
    use_campaign_rustup
    nightly_version=$(rustc "+$nightly" --version)
    [[ "$(rustc +nightly --version)" == "$nightly_version" ]] ||
        die "central nightly alias must match the campaign compiler"
    allow_test_panics=${RUST_SKILLS2_ALLOW_TEST_PANICS:-false}
    [[ "$allow_test_panics" == true || "$allow_test_panics" == false ]] ||
        die "RUST_SKILLS2_ALLOW_TEST_PANICS must be true or false"
    stable_version=$(rustc "+$stable" --version)
    check_compilers
    skills_revision=$(git -C "$SKILLS" rev-parse HEAD)
    clean_policy
    common=$(git_repo rev-parse --path-format=absolute --git-common-dir)
    id=$(printf '%s' "$target" | git hash-object --stdin)
    registry="$common/lint-campaigns/$id"
    mkdir -p "$common/lint-campaigns"
    exec {reg_fd}>"$common/lint-campaigns/$id.lock"; flock -x "$reg_fd"
    [[ ! -e "$registry" ]] || die "active campaign already registered: $(cat "$registry")"
    [[ ! -e "$state" && ! -e "$workroot" ]] || die "use new state and worktree directories"
    git_repo fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$target:refs/remotes/origin/$target"
    base=$(git_repo rev-parse "refs/remotes/origin/$target")
    mkdir -p "$state"/{claims,deferred,inventory,logs,locks,build,queue} "$workroot"
    jq -n --arg repo "$repo" --arg target "$target" --arg base "$base" \
        --arg workroot "$workroot" --arg id "$id" --arg registry "$registry" \
        --arg smoke "$smoke" --arg skills "$skills_revision" \
        --arg nightly "$nightly" --arg stable "$stable" --arg test_panics "$allow_test_panics" \
        --arg nv "$nightly_version" --arg sv "$stable_version" --arg home "$rustup_home" \
        '{repo:$repo,target:$target,base:$base,workroot:$workroot,id:$id,registry:$registry,
          smoke:$smoke,skills_revision:$skills,nightly:$nightly,stable:$stable,rustup_home:$home,
          nightly_version:$nv,stable_version:$sv,allow_test_panics:$test_panics}' >"$state/config.json"
    if [[ -n "$manifest" ]]; then
        cp -- "$manifest" "$state/issues.json"
        # Do not register an issue campaign on a nonzero strict baseline.
        inventory_tip "$base"
        if [[ "$(jq length "$state/inventory/$base.json")" != 0 ]]; then
            printf '%s\n' "$base" >"$state/stopped"
            die "issue campaign requires a clean strict baseline; retained diagnostic evidence in $state"
        fi
    fi
    printf '%s\n' "$state" >"$registry"
    flock -u "$reg_fd"; exec {reg_fd}>&-
    inventory_tip "$base"
    say "campaign initialized at $base"
    exit 0
fi
state=$(realpath -e "$state")
config="$state/config.json"
[[ -f "$config" ]] || die "campaign not initialized"
repo=$(jq -er .repo "$config"); target=$(jq -er .target "$config")
base=$(jq -er .base "$config"); id=$(jq -er .id "$config")
workroot=$(jq -er .workroot "$config"); registry=$(jq -er .registry "$config")
smoke=$(jq -er .smoke "$config"); nightly=$(jq -er .nightly "$config")
stable=$(jq -er .stable "$config"); nightly_version=$(jq -er .nightly_version "$config")
stable_version=$(jq -er .stable_version "$config"); skills_revision=$(jq -er .skills_revision "$config")
allow_test_panics=$(jq -er .allow_test_panics "$config")
rustup_home=$(jq -r '.rustup_home // ""' "$config")
if [[ "$action" == serve && ! -e "$registry" && ( -f "$state/finished" || -f "$state/stopped" ) ]]; then exit 0; fi
[[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign not active"
if [[ "$action" != upgrade && -e "$state/migrating" ]]; then die "campaign migration in progress"; fi
if [[ "$action" != upgrade ]]; then use_campaign_rustup; fi
case "$action" in
    upgrade)
        [[ $# -le 1 ]] || die "upgrade accepts an optional isolated Rustup home"
        if [[ $# -eq 1 ]]; then
            rustup_home=$1
            [[ -n "$rustup_home" ]] || die "Rustup home must not be empty"
            [[ -e "$state/migrating" ]] || die "pause the campaign before changing its Rustup home"
        fi
        use_campaign_rustup
        if [[ -n "$rustup_home" ]]; then check_compilers; fi
        clean_policy
        git -C "$SKILLS" diff --quiet "$skills_revision" HEAD -- \
            scripts/strict_clippy.sh scripts/check_source_lint_policy.py \
            scripts/workspace_test_policy.py .github/actions/rust-strict ||
            die "lint policy changed; cannot reuse existing inventories"
        lock_claims
        mkdir -p "$state/queue"
        jq --arg rev "$(git -C "$SKILLS" rev-parse HEAD)" --arg home "$rustup_home" \
            '.skills_revision=$rev | .rustup_home=$home' "$config" >"$config.tmp"
        mv "$config.tmp" "$config"
        rm -f "$state/migrating"
        unlock_claims
        say "upgraded campaign in place; claims preserved"
        ;;
    issues)
        [[ $# -eq 0 && -f "$state/issues.json" ]] || die "issues requires an issue campaign"
        tip=$(remote_tip)
        lock_claims
        issue_status "$tip" | jq 'map(del(.files))'
        unlock_claims
        ;;
    amend-issues)
        [[ $# == 1 ]] || die "amend-issues requires MANIFEST"
        amend_issues "$1"
        ;;
    claim-issue)
        [[ $# -ge 1 && $# -le 2 ]] || die "claim-issue requires WORKER [ISSUE_ID]"
        claim_issue "${2:-}" "$1"
        ;;
    results)
        [[ $# -le 1 ]] || die "results accepts optional WORKER"
        queue_records | jq --arg worker "${1:-}" \
          '[.[]|select($worker=="" or .worker==$worker)|{job,worker,issue,status,files,source,detail}]'
        ;;
    serve|drain)
        [[ $# -eq 0 ]] || die "unexpected validator arguments"
        check_tools
        say "validator Cargo compilation jobs: $CARGO_BUILD_JOBS (minimum 16)"
        while [[ -f "$registry" && ! -e "$state/migrating" ]]; do
            validator_lock
            drain_queue
            validator_unlock
            [[ "$action" == serve ]] || break
            sleep 2
        done
        ;;
    recover)
        [[ $# -eq 2 && "$1" =~ ^[0-9]{9}$ ]] || die "recover requires JOB WORKER"
        job=$1; worker=$2; lock_worker; check_tools
        record="$state/queue/$job.json"
        lock_claims
        [[ -f "$record" && "$(jq -er .status "$record")" == failed ]] || die "job not failed"
        claim="$state/claims/$worker.json"
        [[ ! -e "$claim" ]] || die "worker has active claim"
        work="$workroot/$worker"
        topic="lint-campaign/${id:0:12}/$worker-$(date +%s%N)"
        source=$(jq -er .source "$record")
        git_repo worktree add --quiet -b "$topic" "$work" "$source"
        jq --arg worker "$worker" --arg work "$work" --arg topic "$topic" \
            '{worker:$worker,base,worktree:$work,branch:$topic,files,cleanup_refs,issue,issue_title}'  "$record" >"$claim.tmp"
        mv "$claim.tmp" "$claim"
        queue_update "$record" recovered "reassigned to $worker"
        unlock_claims
        cat "$claim"
        if [[ -f "$state/logs/queue-$job.conflict.json" && -f "$state/issues.json" ]]; then
            tip=$(remote_tip)
            if git_work merge --no-edit "$tip"; then
                say "recovered conflict job against $tip; inspect combined changes before publishing"
            elif [[ -n "$(git_work diff --name-only --diff-filter=U)" ]]; then
                say "resolve merge conflicts in $work, commit the merge, run focused tests and publish"
                git_work status --short
            else
                die "merge failed without unmerged files; claim retained at $work"
            fi
        fi
        ;;
    refresh|status)
        [[ $# -eq 0 ]] || die "unexpected arguments"
        check_tools
        tip=$(remote_tip)
        [[ -f "$state/inventory/$tip.json" ]] || die "target inventory not cached; serial validator will refresh it"
        printf 'Target %s at %s: %s distinct findings\n' "$target" "$tip" "$(jq length "$state/inventory/$tip.json")"
        jq 'group_by(.file) | map({file:.[0].file,findings:length}) |
            sort_by(-.findings,.file)' "$state/inventory/$tip.json"
        lock_claims
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        if (("${#claims[@]}" > 0)); then jq -s '.' "${claims[@]}"; else printf '[]\n'; fi
        printf 'Deferred files (automatically eligible if their blob changes):\n'
        deferred=("$state/deferred/"*.json)
        if (("${#deferred[@]}" > 0)); then jq -s '.' "${deferred[@]}"; else printf '[]\n'; fi
        printf 'Submission queue:\n'
        queue_records | jq 'map({job,worker,status,files,detail})'
        unlock_claims
        ;;
    claim)
        [[ ! -f "$state/issues.json" ]] || die "use claim-issue for issue campaigns"
        [[ $# -ge 1 && $# -le 4 ]] || die "claim requires WORKER [BUDGET] [PREFIX] [MAX_FILES]"
        worker=$1; lock_worker
        budget=${2:-20}; prefix=${3:-}; max_files=${4:-4}
        [[ "$budget" =~ ^[1-9][0-9]{0,3}$ && "$max_files" =~ ^[1-9][0-9]{0,2}$ ]] ||
            die "invalid budget or maximum files"
        check_tools
        for attempt in 1 2 3 4; do
            tip=$(remote_tip)
            [[ -f "$state/inventory/$tip.json" ]] || die "target inventory not cached; retry after validator refresh"
            lock_claims
            [[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign closed during claim"
            [[ "$(git_repo rev-parse "refs/remotes/origin/$target")" != "$tip" ]] || break
            unlock_claims
            [[ "$attempt" != 4 ]] || die "target kept advancing; retry claim"
        done
        claim="$state/claims/$worker.json"
        [[ ! -e "$claim" ]] || die "worker already owns a claim: $claim"
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        occupied=$(reserved_queue)
        if (("${#claims[@]}" > 0)); then
            occupied=$(jq -s --argjson queued "$occupied" '[.[].files[]]+$queued' "${claims[@]}")
        fi
        for deferred in "$state/deferred/"*.json; do
            file=$(jq -er .file "$deferred")
            if blob=$(git_repo rev-parse "$tip:$file" 2>/dev/null) &&
                [[ "$blob" == "$(jq -er .blob "$deferred")" ]]; then
                occupied=$(jq -c --arg file "$file" '.+[$file]' <<<"$occupied")
            fi
        done
        # A large workspace's tracked-path list can exceed execve's
        # per-argument size limit; read it from a per-claim temporary file.
        tracked=$(mktemp "$state/inventory/.tracked.XXXXXX")
        git_repo ls-tree -r -z --name-only "$tip" | jq -Rs 'split("\u0000") | map(select(length>0))' >"$tracked"
        files=$(jq -c --argjson occupied "$occupied" --slurpfile tracked "$tracked" --arg prefix "$prefix" \
            --argjson budget "$budget" --argjson max "$max_files" '
          group_by(.file) | map({file:.[0].file,n:length}) |
          map(select(.file|endswith(".rs") and startswith($prefix))) |
          map(select(.file as $f | ($occupied|index($f))==null and ($tracked[0]|index($f))!=null)) |
          reduce .[] as $f ({files:[],n:0,done:false};
              if .done then . elif (.files|length)==0 or
                 ((.n+$f.n)<=$budget and (.files|length)<$max)
              then .files += [$f.file] | .n += $f.n
              else .done=true end) | .files
        ' "$state/inventory/$tip.json")
        rm -- "$tracked"
        [[ "$files" != '[]' ]] || die "no unclaimed Rust files matching prefix"
        while IFS= read -r file; do
            valid_file "$file"
            git_repo cat-file -e "$tip:$file" || die "diagnostic file is not tracked: $file"
        done < <(jq -r '.[]' <<<"$files")
        topic="lint-campaign/${id:0:12}/$worker-$(date +%s%N)"
        work="$workroot/$worker"
        git_repo worktree add --quiet -b "$topic" "$work" "$tip"
        jq -n --arg worker "$worker" --arg base "$tip" --arg work "$work" --arg topic "$topic" \
            --argjson files "$files" '{worker:$worker,base:$base,worktree:$work,branch:$topic,files:$files}' >"$claim.tmp"
        mv -- "$claim.tmp" "$claim"
        unlock_claims
        cat "$claim"
        jq --argjson files "$files" '[.[] | select(.file as $f | ($files|index($f))!=null)]' "$state/inventory/$tip.json"
        ;;
    extend)
        [[ $# -ge 2 ]] || die "extend requires WORKER FILE..."
        load_worker "$1"; shift
        for file in "$@"; do valid_file "$file"; done
        extra=$(printf '%s\n' "$@" | jq -Rs 'split("\n") | map(select(length>0))')
        lock_claims
        shopt -s nullglob
        if [[ ! -f "$state/issues.json" ]]; then
            claims=("$state/claims/"*.json)
            jq -es --arg worker "$worker" --argjson extra "$extra" --argjson queued "$(reserved_queue)" '
                ([.[]|select(.worker!=$worker)|.files[]]+$queued) as $other |
                all($extra[]; . as $f | ($other|index($f))==null)
            ' "${claims[@]}" >/dev/null || die "file already claimed by another worker"
        fi
        jq --argjson extra "$extra" '.files=(.files+$extra|unique)' "$claim" >"$claim.tmp"
        mv -- "$claim.tmp" "$claim"
        unlock_claims
        cat "$claim"
        ;;
    checkpoint)
        [[ $# -eq 1 ]] || die "checkpoint requires WORKER"
        load_worker "$1"; clean_at "$work"
        tip=$(remote_tip); revision=$(git_work rev-parse HEAD)
        shared=$(git_repo merge-base "$tip" "$revision")
        scope_diff "$shared" "$revision"
        git_work push origin "$revision:refs/heads/$topic"
        ;;
    publish)
        [[ $# -ge 1 && $# -le 2 ]] || die "publish requires WORKER [FOCUSED_TEST_COMMAND]"
        focused=${2:-:}
        if [[ -f "$state/issues.json" ]]; then
            [[ $# == 2 && -n "$focused" && "$focused" != : ]] || die "issue submission requires focused regression command"
        fi
        load_worker "$1"; check_tools; clean_at "$work"
        enqueue
        ;;
    release)
        [[ $# -eq 1 ]] || die "release requires WORKER"
        load_worker "$1"; tip=$(remote_tip); remove_claim "$tip"
        ;;
    defer)
        [[ ! -f "$state/issues.json" ]] || die "issue claims can be released, not deferred by file"
        [[ $# -eq 2 && -n "$2" ]] || die "defer requires WORKER REASON"
        load_worker "$1"; tip=$(remote_tip); remove_claim "$tip" "$2"
        ;;
    retry)
        [[ $# -ge 1 ]] || die "retry requires FILE..."
        lock_claims
        for file in "$@"; do
            valid_file "$file"
            key=$(printf '%s' "$file" | git hash-object --stdin)
            rm -f -- "$state/deferred/$key.json"
        done
        unlock_claims
        ;;
    stop)
        [[ $# -eq 0 ]] || die "stop takes no additional arguments"
        validator_lock
        lock_claims
        require_empty_queue
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        (("${#claims[@]}" == 0)) || die "active claims remain"
        tip=$(remote_tip)
        printf '%s\n' "$tip" >"$state/stopped"
        if [[ -d "$workroot/.validator" ]]; then git_repo worktree remove "$workroot/.validator"; fi
        rm -rf -- "$state/build/validator"
        rm -- "$registry"
        unlock_claims
        say "stopped without declaring strict success; evidence retained in $state"
        ;;
    finish)
        [[ $# -le 1 ]] || die "finish accepts an optional full test command"
        check_tools
        # Exclude the serial validator and assignments during final checks.
        validator_lock
        lock_claims
        require_empty_queue
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        (("${#claims[@]}" == 0)) || die "active claims remain"
        require_finished_issues
        tip=$(remote_tip)
        temporary=$(mktemp -d "$workroot/.finish.XXXXXX")
        build=$(mktemp -d "$state/build/final.XXXXXX")
        (
            trap 'git_repo worktree remove "$temporary" >/dev/null 2>&1 || true; rmdir "$temporary" 2>/dev/null || true; rm -rf -- "$build"' EXIT
            git_repo worktree add --quiet --detach "$temporary" "$tip" || exit
            cd "$temporary" || exit
            export CARGO_TARGET_DIR="$build/target" CARGO_INCREMENTAL=0
            export GITHUB_WORKSPACE="$temporary" RUST_SKILLS2_WORKING_DIRECTORY=.
            export RUST_SKILLS2_ACTION_DIR="$SKILLS/.github/actions/rust-strict"
            export RUST_SKILLS2_CARGO_ARGS="--locked --workspace --all-targets"
            export RUST_SKILLS2_ALLOW_TEST_PANICS="$allow_test_panics"
            bash "$SKILLS/scripts/strict_clippy.sh" || exit
            bash -euo pipefail -c "${1:-cargo +stable test --workspace --locked}"
        ) >"$state/logs/$tip.final.log" 2>&1 || die "final strict gate failed: $state/logs/$tip.final.log"
        [[ "$(remote_tip)" == "$tip" ]] || die "target advanced during final verification"
        printf '%s\n' "$tip" >"$state/finished"
        if [[ -d "$workroot/.validator" ]]; then git_repo worktree remove "$workroot/.validator"; fi
        rm -rf -- "$state/build/validator"
        rm -- "$registry"
        unlock_claims
        say "finished $tip; logs retained in $state"
        ;;
    *) usage; die "unknown command: $action" ;;
esac
