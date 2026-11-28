# Sourced by lint_campaign.sh. All paths/configuration belong to its campaign.
# shellcheck shell=bash
# These functions are sourced by lint_campaign.sh; its shared state is initialized there.
# shellcheck disable=SC2154
queue_records() {
    local -a records
    shopt -s nullglob
    records=("$state/queue/"*.json)
    if (("${#records[@]}")); then jq -s '.' "${records[@]}"; else printf '[]\n'; fi
}
# Caller holds claims.lock. Retry an interrupted running job first.
# In issue campaigns rank pending jobs by unique unfinished transitive
# dependants, then FIFO. Lint-only campaigns retain their FIFO policy.
next_validation_job() {
    if [[ ! -f "$state/issues.json" ]]; then
        queue_records | jq -r '
          map(select(.status=="pending" or .status=="running"))
          | sort_by((.status!="running"),.job) | .[0].job // empty'
        return
    fi
    queue_records | jq -r --slurpfile tasks "$state/issues.json" '
      . as $queue |
      [$queue[] | select(.status=="published") | .issue] as $done |
      # The validated manifest is topologically ordered. Deduplicate each
      # ancestor set so diamonds are not counted multiple times.
      (reduce $tasks[0][] as $task ({};
        . as $known | .[$task.id] =
          ([$task.depends[] as $dep | $dep, $known[$dep][]] | unique)
      )) as $ancestors |
      (reduce ($tasks[0][] | select(.id as $id | ($done|index($id))==null)) as $task ({};
        reduce $ancestors[$task.id][] as $ancestor (.;
          .[$ancestor] = ((.[$ancestor] // 0) + 1))
      )) as $impact |
      map(select(.status=="pending" or .status=="running")) |
      sort_by((.status!="running"), -($impact[.issue] // 0), .job) |
      .[0].job // empty'
}
reserved_queue() {
    queue_records | jq -c '[.[] | select(.status=="staging" or .status=="pending" or .status=="running" or .status=="failed") | .files[]]'
}
queue_update() {
    local record=$1 status=$2 detail=${3:-}
    jq --arg status "$status" --arg detail "$detail" \
        '.status=$status | .detail=$detail' "$record" >"$record.tmp"
    mv -- "$record.tmp" "$record"
}
next_job() {
    local n=0
    if [[ -f "$state/sequence" ]]; then read -r n <"$state/sequence"; fi
    n=$((n+1))
    printf '%s\n' "$n" >"$state/sequence.tmp"
    mv "$state/sequence.tmp" "$state/sequence"
    printf '%09d' "$n"
}
enqueue() {
    local revision tip shared job record queue_branch staging
    revision=$(git_work rev-parse HEAD)
    tip=$(remote_tip)
    if git_repo merge-base --is-ancestor "$revision" "$tip"; then
        remove_claim "$tip"
        say "already integrated: $revision"
        return
    fi
    shared=$(git_repo merge-base "$tip" "$revision")
    scope_diff "$shared" "$revision"
    lock_claims
    staging=$(queue_records | jq -r --arg w "$worker" --arg r "$revision" \
        'map(select(.status=="staging" and .worker==$w and .source==$r))|.[0].job // empty')
    if [[ -n "$staging" ]]; then
        job=$staging
        record="$state/queue/$job.json"
        queue_branch=$(jq -er .queue_branch "$record")
    else
        job=$(next_job)
        record="$state/queue/$job.json"
        queue_branch="lint-campaign/${id:0:12}/queue-$job"
        git_repo update-ref "refs/heads/$queue_branch" "$revision" ""
        jq --arg job "$job" --arg source "$revision" --arg branch "$queue_branch" \
            --arg focused "$focused" --arg oracle "${NGSPICE_BIN:-}" \
            '. + {job:$job,source:$source,queue_branch:$branch,focused:$focused,oracle:$oracle,status:"staging",
              cleanup_refs:((.cleanup_refs // []) + [.branch,$branch] | unique),detail:""}' \
            "$claim" >"$record.tmp"
        mv "$record.tmp" "$record"
    fi
    unlock_claims
    # Durable submission; no validation or target write in an editor process.
    git_repo push origin "$revision:refs/heads/$queue_branch"
    lock_claims
    clean_at "$work"
    [[ "$(git_work rev-parse HEAD)" == "$revision" ]] || die "claim changed during submission"
    git_repo worktree remove "$work"
    git_repo update-ref -d "refs/heads/$topic" "$revision"
    rm -- "$claim"
    queue_update "$record" pending "ready for serial validator"
    unlock_claims
    rm -rf -- "$state/build/$worker"
    printf 'Queued %s (%s); worker %s is free to claim again.\n' "$job" "$revision" "$worker"
}
validator_lock() {
    exec {validator_fd}>"$state/validator.lock"
    flock -n "$validator_fd" || die "validator already active"
}
validator_unlock() {
    flock -u "$validator_fd"
    exec {validator_fd}>&-
}
validator_checkout() {
    local revision=$1
    work="$workroot/.validator"
    if [[ -d "$work" ]]; then
        # Only the exclusively locked validator owns this disposable checkout.
        [[ -z "$(git_work symbolic-ref -q HEAD || true)" ]] || die "validator is not detached"
        git_work reset --hard --quiet "$revision"
        git_work clean -fd --quiet
    else
        git_repo worktree add --quiet --detach "$work" "$revision"
    fi
    clean_at "$work"
}
cleanup_submission_refs() {
    local accepted=$1 branch ref found sha
    while IFS= read -r branch; do
        ref="refs/heads/$branch"
        found=$(git_repo ls-remote --heads origin "$ref") || continue
        if [[ -n "$found" ]]; then
            sha=${found%%$'\t'*}
            if git_repo merge-base --is-ancestor "$sha" "$accepted"; then
                git_repo push --force-with-lease="$ref:$sha" origin ":$ref" ||
                    say "retained remote checkpoint $ref"
            fi
        fi
        if sha=$(git_repo rev-parse --verify "$ref" 2>/dev/null) &&
            git_repo merge-base --is-ancestor "$sha" "$accepted"; then
            git_repo update-ref -d "$ref" "$sha" || true
        fi
    done < <(jq -r '.cleanup_refs[]' "$claim")
}
validate_job() {
    local record=$1 tip source revision shared oracle job
    claim=$record
    worker=$(jq -er .worker "$record")
    job=$(jq -er .job "$record")
    source=$(jq -er .source "$record")
    focused=$(jq -er .focused "$record")
    oracle=$(jq -r '.oracle // ""' "$record")
    if [[ -n "$oracle" ]]; then export NGSPICE_BIN="$oracle"; fi
    tip=$(remote_tip)
    if git_repo merge-base --is-ancestor "$source" "$tip"; then
        revision=$tip
    else
        validator_checkout "$tip"
        shared=$(git_repo merge-base "$tip" "$source")
        scope_diff "$shared" "$source"
        if [[ "$direct_default" != true || ! -f "$state/issues.json" ]]; then
            inventory "$work" "$tip" "$state/build/validator"
        fi
        if ! git_work merge --no-edit "$source"; then
            if [[ -f "$state/issues.json" ]]; then
                git_work diff --name-only --diff-filter=U -z |
                    jq -Rs --arg tip "$tip" --arg source "$source" \
                        '{target:$tip,source:$source,paths:(split("\u0000")|map(select(length>0)))}' \
                        >"$state/logs/queue-$job.conflict.tmp"
                if jq -e '.paths|length>0' "$state/logs/queue-$job.conflict.tmp" >/dev/null; then
                    mv "$state/logs/queue-$job.conflict.tmp" "$state/logs/queue-$job.conflict.json"
                else
                    rm -f "$state/logs/queue-$job.conflict.tmp"
                fi
            fi
            die "merge failed; recover job $job to reconcile against current target"
        fi
        revision=$(git_work rev-parse HEAD)
        scope_diff "$tip" "$revision"
        # Direct-main issue campaigns have one whole-workspace policy gate:
        # the repository's actual hosted CI. Do not apply a second, pinned
        # historical Clippy inventory or require unrelated main debt to vanish
        # before focused implementation work can be published.
        if [[ "$direct_default" != true || ! -f "$state/issues.json" ]]; then
            inventory "$work" "$revision" "$state/build/validator"
            compare_inventory "$tip" "$revision"
        fi
        git_work diff --no-color -U0 "$tip" "$revision" >"$state/logs/$revision.patch"
        validate "$revision"
        # The sole validator is the only campaign writer. Never force-push.
        if ! git_work push origin "$revision:refs/heads/$target"; then
            if [[ "$(remote_tip)" != "$tip" ]]; then
                touch "$state/logs/queue-$job.retry"
            fi
            die "target publication failed"
        fi
    fi
    printf '%s\n' "$revision" >"$state/queue/$job.merged.tmp"
    mv "$state/queue/$job.merged.tmp" "$state/queue/$job.merged"
    cleanup_submission_refs "$revision"
}
drain_queue() {
    local job record rc tip staged old_claim original workpath source queue_ref
    while [[ -f "$registry" && ! -e "$state/migrating" ]]; do
        lock_claims
        expire_claims
        # Recover a crash after removing the editor worktree but before
        # marking its durable submission pending.
        while IFS= read -r staged; do
            record="$state/queue/$staged.json"
            workpath=$(jq -er .worktree "$record")
            [[ ! -e "$workpath" ]] || continue
            source=$(jq -er .source "$record")
            queue_ref="refs/heads/$(jq -er .queue_branch "$record")"
            [[ "$(git_repo rev-parse "$queue_ref")" == "$source" ]] || continue
            old_claim="$state/claims/$(jq -er .worker "$record").json"
            original=$(jq -er .branch "$record")
            if [[ -f "$old_claim" && "$(jq -er .branch "$old_claim")" == "$original" ]]; then
                git_repo update-ref -d "refs/heads/$original" "$source" || true
                rm -- "$old_claim"
            fi
            queue_update "$record" pending "recovered interrupted submission"
        done < <(queue_records | jq -r '.[]|select(.status=="staging")|.job')
        # A crashed running job is retried, checking ancestry before rebuilding.
        job=$(next_validation_job)
        if [[ -z "$job" ]]; then
            unlock_claims
            tip=$(git_repo rev-parse "refs/remotes/origin/$target")
            if [[ ( "$direct_default" != true || ! -f "$state/issues.json" ) && ! -f "$state/inventory/$tip.json" ]]; then
                inventory_tip "$tip"
            fi
            reconcile_when_idle
            return
        fi
        record="$state/queue/$job.json"
        rm -f "$state/logs/queue-$job.conflict.json" "$state/logs/queue-$job.retry"
        queue_update "$record" running "validating against latest target"
        unlock_claims
        say "validating queue job $job"
        # An if-condition would disable errexit throughout the function.
        set +e
        (
            set -e
            # Used by the EXIT trap below.
            # shellcheck disable=SC2034
            started=$SECONDS
            # The validator lock is held here. No other job can use this
            # directory; discard any leftovers from an interrupted job.
            build="$state/build/validator"
            rm -rf -- "$build"
            mkdir -p "$build"
            trap 'rc=$?; rm -rf -- "$build"; printf "Timing: validation transaction %ss (exit %s)\n" "$((SECONDS-started))" "$rc"' EXIT
            validate_job "$record"
        ) >>"$state/logs/queue-$job.log" 2>&1
        rc=$?
        set -e
        lock_claims
        if ((rc==0)); then
            queue_update "$record" published "$(cat "$state/queue/$job.merged")"
        elif [[ -f "$state/logs/queue-$job.retry" ]]; then
            queue_update "$record" pending "target advanced during publication; retry on latest main"
        elif [[ -f "$state/logs/queue-$job.conflict.json" ]]; then
            queue_update "$record" failed "merge conflict; recover $job to reconcile against current target"
        else
            queue_update "$record" failed "exit $rc; see $state/logs/queue-$job.log"
        fi
        unlock_claims
        say "queue job $job $(jq -r .status "$record")"
        if ((rc==0)); then
            close_published_issue "$record" "$(cat "$state/queue/$job.merged")" || true
        fi
    done
}
require_empty_queue() {
    [[ "$(reserved_queue)" == '[]' ]] || die "queued, running or failed submissions remain"
}
