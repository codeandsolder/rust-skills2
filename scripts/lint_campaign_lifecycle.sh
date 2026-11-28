# Sourced by lint_campaign.sh. Preserve the campaign identity across retargeting.
# shellcheck shell=bash
# These functions are sourced by lint_campaign.sh; its shared state is initialized there.
# shellcheck disable=SC2154
# shellcheck disable=SC2034
retarget_campaign() {
    local destination=$1 old_tip new_tip new_registry new_id default_ref migration reg_fd
    [[ -e "$state/migrating" ]] || die "pause the campaign before retargeting"
    [[ "$destination" != HEAD && "$destination" != "$target" ]] || die "invalid or unchanged target"
    git check-ref-format "refs/heads/$destination" >/dev/null || die "invalid target branch"
    validator_lock
    lock_claims
    check_compilers
    clean_policy
    git -C "$SKILLS" diff --quiet "$skills_revision" HEAD -- scripts/strict_clippy.sh scripts/toolchain-pin.sh scripts/release-licenses.mjs policy-wasm .github/actions/rust-strict || die "lint policy changed; cannot reuse existing inventories"
    old_tip=$(remote_tip)
    git_repo fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$destination:refs/remotes/origin/$destination"
    new_tip=$(git_repo rev-parse "refs/remotes/origin/$destination")
    git_repo merge-base --is-ancestor "$old_tip" "$new_tip" || die "destination must contain the entire previous target history"
    new_id=$(printf '%s' "$destination" | git hash-object --stdin)
    new_registry="$(dirname "$registry")/$new_id"
    exec {reg_fd}>"$new_registry.lock"; flock -x "$reg_fd"
    [[ ! -e "$new_registry" ]] || die "destination already registered"
    default_ref=$(git_repo ls-remote --symref origin HEAD)
    local direct=false
    if [[ "$default_ref" == "ref: refs/heads/$destination"$'\t'HEAD* || "$destination" == main || "$destination" == master ]]; then direct=true; fi
    migration="$state/migrations/retarget-$new_id"
    mkdir -p "$migration"
    cp -- "$config" "$migration/config.json"
    jq --arg target "$destination" --arg registry "$new_registry" --arg rev "$(git -C "$SKILLS" rev-parse HEAD)" --argjson direct "$direct" '.target=$target | .registry=$registry | .skills_revision=$rev | .direct_default=$direct' "$config" >"$config.tmp"
    printf '%s\n' "$state" >"$new_registry.tmp"
    mv -- "$new_registry.tmp" "$new_registry"
    mv -- "$config.tmp" "$config"
    rm -- "$registry"
    rm -- "$state/migrating"
    unlock_claims
    validator_unlock
    say "retargeted $target to $destination at $new_tip; queue, claims and identity preserved"
}
# Close only the issue explicitly represented by a successfully published
# queue record, and only when its accepted commit is reachable from main.
# Failed API calls remain retryable without changing validation acceptance.
close_published_issue() (
    local record=$1 tip=$2 issue job accepted url remote slug ledger close_fd
    [[ "$direct_default" == true && -f "$state/issues.json" ]] || return 0
    issue=$(jq -r '.issue // empty' "$record")
    [[ -n "$issue" ]] || return 0
    ledger="$state/closed-issues/$issue"
    [[ ! -f "$ledger" ]] || return 0
    mkdir -p "$state/closed-issues"
    exec {close_fd}>"$state/locks/close-issue-$issue.lock"
    flock -x "$close_fd"
    [[ ! -f "$ledger" ]] || return 0
    job=$(jq -er .job "$record")
    [[ -f "$state/queue/$job.merged" ]] || return 0
    read -r accepted <"$state/queue/$job.merged"
    git_repo merge-base --is-ancestor "$accepted" "$tip" || return 0
    url=$(jq -r --arg issue "$issue" '.[]|select(.id==$issue)|.url // empty' "$state/issues.json")
    remote=$(git_repo remote get-url origin)
    case "$remote" in
        https://github.com/*) slug=${remote#https://github.com/} ;;
        git@github.com:*) slug=${remote#git@github.com:} ;;
        *) return 0 ;;
    esac
    slug=${slug%.git}
    [[ "$url" == "https://github.com/$slug/issues/$issue" ]] || return 0
    if gh issue close "$url" --reason completed --comment "Accepted into $target at https://github.com/$slug/commit/$accepted."; then
        printf '%s\n' "$accepted" >"$ledger.tmp"
        mv -- "$ledger.tmp" "$ledger"
    else
        say "issue $issue closure failed; run reconcile to retry"
        return 1
    fi
)
reconcile_main_issues() {
    local tip record rc=0
    [[ "$direct_default" == true ]] || die "issue closure requires the default target"
    tip=$(remote_tip)
    while IFS= read -r record; do
        close_published_issue "$state/queue/$record.json" "$tip" || rc=1
    done < <(queue_records | jq -r '.[]|select(.status=="published")|.job')
    return "$rc"
}

reconcile_when_idle() {
    local stamp="$state/lifecycle-last" now
    [[ "$direct_default" == true ]] || return 0
    now=$(date +%s)
    if [[ -f "$stamp" ]] && (( now - $(stat -c %Y "$stamp") < 300 )); then return 0; fi
    touch "$stamp"
    reconcile_main_issues || true
    reconcile_campaign_refs || true
}
