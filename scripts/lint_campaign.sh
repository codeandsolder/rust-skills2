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
  lint_campaign.sh refresh STATE
  lint_campaign.sh status STATE
  lint_campaign.sh claim STATE WORKER [LINT_BUDGET=20] [PATH_PREFIX] [MAX_FILES=4]
  lint_campaign.sh extend STATE WORKER FILE...
  lint_campaign.sh checkpoint STATE WORKER
  lint_campaign.sh publish STATE WORKER
  lint_campaign.sh release STATE WORKER
  lint_campaign.sh finish STATE [FINAL_TEST_COMMAND]

STATE and WORKTREE_ROOT must be absolute, outside repository worktrees.
init runs inside the target Git repository. All workers use the same local
Git common directory and STATE. Remote is origin; TARGET is an existing
temporary topic branch, not main/master. Require the managed RUSTC_WRAPPER.
LINT_CAMPAIGN_NIGHTLY (default nightly) and LINT_CAMPAIGN_STABLE (stable)
are fixed at init, including actual rustc versions.
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
valid_file() {
    [[ "$1" == *.rs && "$1" != /* && "$1" != -* && "$1" != *$'\n'* &&
       "$1" != *$'\r'* && "$1" != *$'\t'* && "/$1/" != *'/../'* &&
       "/$1/" != *'/./'* && "$1" != *'//'* && "$1" != .git/* ]] ||
       die "claim only repository-relative Rust files: $1"
}
git_repo() { git -C "$repo" "$@"; }
git_work() { git -C "$work" "$@"; }
need_cache() {
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
check_tools() {
    need_cache
    [[ "$(rustc "+$nightly" --version)" == "$nightly_version" ]] ||
        die "nightly compiler drift; start a new campaign"
    [[ "$(rustc "+$stable" --version)" == "$stable_version" ]] ||
        die "stable compiler drift; start a new campaign"
    [[ "$(git -C "$SKILLS" rev-parse HEAD)" == "$skills_revision" ]] ||
        die "rust-skills2 revision changed; use the original checkout"
    clean_at "$SKILLS"
}
remote_tip() {
    # Isolate fetch of the target ref; do not touch the checked-out local branch.
    local tip
    git_repo fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$target:refs/remotes/origin/$target" || die "target fetch failed"
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
            cd "$checkout"
            export CARGO_TARGET_DIR="$dir/target" CARGO_INCREMENTAL=0
            export CLIPPY_CONF_DIR="$SKILLS/.github/actions/rust-strict"
            cargo "+$nightly" clippy --locked --workspace --all-targets --keep-going --message-format=json -- \
                -W clippy::pedantic -W clippy::nursery \
                -D clippy::correctness -D clippy::suspicious -D clippy::perf \
                -D clippy::suspicious_operation_groupings
        ) >"$state/logs/$revision.clippy.jsonl" 2>"$state/logs/$revision.clippy.stderr" ||
            die "inventory failed; see $state/logs/$revision.clippy.stderr and .jsonl"
        clean_at "$checkout"
        [[ "$(git -C "$checkout" rev-parse HEAD)" == "$revision" ]] || die "inventory checkout moved"
        snapshot=$(mktemp "$state/inventory/.snapshot.XXXXXX")
        jq -se --arg root "$checkout/" '
          if any(.[]; .reason == "build-finished" and .success == true) then
            [.[] | select(.reason == "compiler-message") | .message as $m |
              select($m.level == "warning") |
              ([ $m.spans[]? | select(.is_primary) ] |
               if length == 0 then [{file_name:"<unlocated>",line_start:0,column_start:0}]
               else . end)[] |
              {file:(.file_name | if startswith($root) then ltrimstr($root) else . end),
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
      {owned_before:$n_before, owned_after:$n_after, outside_increases:$regressions} |
      if $n_after >= $n_before or ($regressions|length)>0 then
        error(tojson) else . end
    ' || die "no owned lint reduction, or new diagnostics outside claim"
}
validate() {
    local revision=$1 dir="$state/build/$worker"
    clean_at "$work"
    (
        cd "$work"
        export CARGO_TARGET_DIR="$dir/target" CARGO_INCREMENTAL=0
        cargo "+$stable" fmt --all -- --check
        cargo "+$stable" clippy --workspace --all-targets --locked -- -D warnings
        uv run --no-project python "$SKILLS/scripts/check_source_lint_policy.py"
        bash -euo pipefail -c "$smoke"
    ) >"$state/logs/$revision.gate.log" 2>&1 ||
        die "regression gate failed; see $state/logs/$revision.gate.log"
    clean_at "$work"
    [[ "$(git_work rev-parse HEAD)" == "$revision" ]] || die "worker changed during checks"
}
remove_claim() {
    local tip=$1 revision checkpoint_ref remote_checkpoint
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
    git_repo worktree remove "$work"
    git_repo update-ref -d "refs/heads/$topic" "$revision"
    rm -- "$claim"
    rm -rf -- "$state/build/$worker"
    unlock_claims
}
if [[ "$action" == init ]]; then
    [[ $# -ge 2 && $# -le 3 ]] || die "init requires TARGET WORKTREE_ROOT [SMOKE_COMMAND]"
    target=$1; workroot=$2; smoke=${3:-cargo +stable test --workspace --locked}
    repo=$(git rev-parse --show-toplevel)
    repo=$(realpath "$repo")
    [[ "$target" != main && "$target" != master && "$target" != HEAD ]] ||
        die "use a temporary integration/topic branch"
    git check-ref-format "refs/heads/$target" >/dev/null || die "invalid target branch"
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
    nightly_version=$(rustc "+$nightly" --version)
    stable_version=$(rustc "+$stable" --version)
    skills_revision=$(git -C "$SKILLS" rev-parse HEAD)
    clean_at "$SKILLS"
    common=$(git_repo rev-parse --path-format=absolute --git-common-dir)
    id=$(printf '%s' "$target" | git hash-object --stdin)
    registry="$common/lint-campaigns/$id"
    mkdir -p "$common/lint-campaigns"
    exec {reg_fd}>"$common/lint-campaigns/$id.lock"; flock -x "$reg_fd"
    [[ ! -e "$registry" ]] || die "active campaign already registered: $(cat "$registry")"
    [[ ! -e "$state" && ! -e "$workroot" ]] || die "use new state and worktree directories"
    git_repo fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$target:refs/remotes/origin/$target"
    base=$(git_repo rev-parse "refs/remotes/origin/$target")
    mkdir -p "$state"/{claims,inventory,logs,locks,build} "$workroot"
    jq -n --arg repo "$repo" --arg target "$target" --arg base "$base" \
        --arg workroot "$workroot" --arg id "$id" --arg registry "$registry" \
        --arg smoke "$smoke" --arg skills "$skills_revision" \
        --arg nightly "$nightly" --arg stable "$stable" \
        --arg nv "$nightly_version" --arg sv "$stable_version" \
        '{repo:$repo,target:$target,base:$base,workroot:$workroot,id:$id,registry:$registry,
          smoke:$smoke,skills_revision:$skills,nightly:$nightly,stable:$stable,
          nightly_version:$nv,stable_version:$sv}' >"$state/config.json"
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
[[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign not active"
case "$action" in
    refresh|status)
        [[ $# -eq 0 ]] || die "unexpected arguments"
        check_tools
        tip=$(remote_tip)
        inventory_tip "$tip"
        printf 'Target %s at %s\n' "$target" "$tip"
        jq 'group_by(.file) | map({file:.[0].file,findings:length}) |
            sort_by(-.findings,.file)' "$state/inventory/$tip.json"
        lock_claims
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        if (("${#claims[@]}" > 0)); then jq -s '.' "${claims[@]}"; else printf '[]\n'; fi
        unlock_claims
        ;;
    claim)
        [[ $# -ge 1 && $# -le 4 ]] || die "claim requires WORKER [BUDGET] [PREFIX] [MAX_FILES]"
        worker=$1; lock_worker
        budget=${2:-20}; prefix=${3:-}; max_files=${4:-4}
        [[ "$budget" =~ ^[1-9][0-9]{0,3}$ && "$max_files" =~ ^[1-9][0-9]{0,2}$ ]] ||
            die "invalid budget or maximum files"
        check_tools
        tip=$(remote_tip); inventory_tip "$tip"
        lock_claims
        [[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign closed during claim"
        claim="$state/claims/$worker.json"
        [[ ! -e "$claim" ]] || die "worker already owns a claim: $claim"
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        occupied='[]'
        if (("${#claims[@]}" > 0)); then occupied=$(jq -s '[.[].files[]]' "${claims[@]}"); fi
        files=$(jq -c --argjson occupied "$occupied" --arg prefix "$prefix" \
            --argjson budget "$budget" --argjson max "$max_files" '
          group_by(.file) | map({file:.[0].file,n:length}) |
          map(select(.file|endswith(".rs") and startswith($prefix))) |
          map(select(.file as $f | ($occupied|index($f))==null)) |
          reduce .[] as $f ({files:[],n:0,done:false};
              if .done then . elif (.files|length)==0 or
                 ((.n+$f.n)<=$budget and (.files|length)<$max)
              then .files += [$f.file] | .n += $f.n
              else .done=true end) | .files
        ' "$state/inventory/$tip.json")
        [[ "$files" != '[]' ]] || die "no unclaimed Rust files matching prefix"
        while IFS= read -r file; do
            valid_file "$file"
            git_repo cat-file -e "$tip:$file" || die "diagnostic file is not tracked: $file"
        done < <(jq -r '.[]' <<<"$files")
        topic="lint-campaign/${id:0:12}/$worker"
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
        claims=("$state/claims/"*.json)
        jq -es --arg worker "$worker" --argjson extra "$extra" '
            [.[]|select(.worker!=$worker)|.files[]] as $other |
            all($extra[]; . as $f | ($other|index($f))==null)
        ' "${claims[@]}" >/dev/null || die "file already claimed by another worker"
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
        [[ $# -eq 1 ]] || die "publish requires WORKER"
        load_worker "$1"; check_tools; clean_at "$work"
        for attempt in 1 2 3 4; do
            tip=$(remote_tip)
            revision=$(git_work rev-parse HEAD)
            if git_repo merge-base --is-ancestor "$revision" "$tip"; then
                remove_claim "$tip"; say "already integrated: $revision"; exit 0
            fi
            shared=$(git_repo merge-base "$tip" "$revision")
            scope_diff "$shared" "$revision"
            # Preserve both workers' commits, without rewriting checkpoint history.
            git_work merge --no-edit "$tip" || die "resolve merge conflict in $work before retrying"
            revision=$(git_work rev-parse HEAD)
            scope_diff "$tip" "$revision"
            inventory_tip "$tip"
            inventory "$work" "$revision" "$state/build/$worker"
            compare_inventory "$tip" "$revision"
            git_work diff --no-color -U0 "$tip" "$revision" >"$state/logs/$revision.patch"
            validate "$revision"
            # No force, no lease override: the destination must fast-forward.
            if git_work push origin "$revision:refs/heads/$target"; then
                remove_claim "$revision"
                say "published $revision to $target"
                exit 0
            fi
            newer=$(remote_tip)
            [[ "$newer" != "$tip" ]] || die "push failed without target advancement; inspect Git output"
            say "target advanced; incorporate $newer and revalidate (attempt $attempt)"
        done
        die "target kept advancing; retain claim and retry publish"
        ;;
    release)
        [[ $# -eq 1 ]] || die "release requires WORKER"
        load_worker "$1"; tip=$(remote_tip); remove_claim "$tip"
        ;;
    finish)
        [[ $# -le 1 ]] || die "finish accepts an optional full test command"
        check_tools
        # Hold claims lock during finish: no new work may be assigned while
        # proving the final state. All existing claims must be released.
        lock_claims
        shopt -s nullglob
        claims=("$state/claims/"*.json)
        (("${#claims[@]}" == 0)) || die "active claims remain"
        tip=$(remote_tip)
        temporary=$(mktemp -d "$workroot/.finish.XXXXXX")
        (
            trap 'git_repo worktree remove "$temporary" >/dev/null 2>&1 || true; rmdir "$temporary" 2>/dev/null || true' EXIT
            git_repo worktree add --quiet --detach "$temporary" "$tip"
            cd "$temporary"
            export CARGO_TARGET_DIR="$state/build/final/target" CARGO_INCREMENTAL=0
            # The central script explicitly uses +nightly; compare its compiler.
            [[ "$(rustc +nightly --version)" == "$nightly_version" ]] ||
                die "central gate nightly differs from campaign nightly"
            bash "$SKILLS/scripts/strict_clippy.sh"
            bash -euo pipefail -c "${1:-cargo +stable test --workspace --locked}"
        ) >"$state/logs/$tip.final.log" 2>&1 || die "final strict gate failed: $state/logs/$tip.final.log"
        rm -rf -- "$state/build/final"
        [[ "$(remote_tip)" == "$tip" ]] || die "target advanced during final verification"
        printf '%s\n' "$tip" >"$state/finished"
        rm -- "$registry"
        unlock_claims
        say "finished $tip; logs retained in $state"
        ;;
    *) usage; die "unknown command: $action" ;;
esac
