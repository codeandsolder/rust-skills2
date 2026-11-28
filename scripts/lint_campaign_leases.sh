# shellcheck shell=bash
# Claims are editor leases, not submission leases. The caller holds claims.lock
# and the relevant worker lock (sweeps acquire worker locks non-blockingly).
expire_claim() {
    local record=$1 now=$2 cutoff work gitdir recent owner branch job
    [[ -f "$record" ]] || return 0
    cutoff=$((now - 900))
    if (( $(stat -c %Y -- "$record") > cutoff )); then return 0; fi
    work=$(jq -er .worktree "$record")
    if [[ -d "$work" ]]; then
        gitdir=$(git -C "$work" rev-parse --absolute-git-dir) || return 0
        # Include ctime: editors may preserve mtime; directory changes capture
        # deletions. Linked-worktree metadata captures commits and index edits.
        recent=$(find "$work" "$gitdir" \( -newermt "@$cutoff" -o -newerct "@$cutoff" \) -printf 1 -quit) || return 0
        [[ -z "$recent" ]] || return 0
    fi
    owner=$(jq -er .worker "$record")
    branch=$(jq -er .branch "$record")
    mkdir -p "$state/expired"
    # An interrupted staging operation still owns its queued source. Make it
    # recoverable instead of leaving a permanent staging reservation. If its
    # worktree is already gone, the ordinary queue recovery handles it.
    if [[ -e "$work" ]]; then
        while IFS= read -r job; do
            queue_update "$state/queue/$job.json" failed "editor lease expired during staging; recover committed source"
        done < <(queue_records | jq -r --arg branch "$branch" \
            '.[]|select(.status=="staging" and .branch==$branch)|.job')
    fi
    # Do not move/delete the worktree, branch, or any unpublished changes.
    # An old worker can no longer submit through the archived claim.
    mv -- "$record" "$state/expired/${branch##*/}.json"
    say "expired idle claim $owner; preserved worktree $work"
}

expire_claims() {
    local now=${1:-$(date +%s)} record owner lease_fd
    local -a records
    shopt -s nullglob
    records=("$state/claims/"*.json)
    for record in "${records[@]}"; do
        owner=$(jq -er .worker "$record")
        exec {lease_fd}>"$state/locks/$owner.lock"
        if flock -n "$lease_fd"; then expire_claim "$record" "$now"; fi
        exec {lease_fd}>&-
    done
}

# Reusing a worker ID must never overwrite a retained expired worktree.
new_worker_worktree() {
    local branch=$2 candidate="$workroot/$1"
    if [[ -e "$candidate" || -L "$candidate" ]]; then
        candidate="$workroot/${branch##*/}"
    fi
    printf '%s\n' "$candidate"
}

# Called with the worker lock held; reject expired claims before renewal.
renew_claim() {
    lock_claims
    expire_claim "$claim" "$(date +%s)"
    [[ -f "$claim" ]] || die "no active claim for $worker (claim may have expired)"
    touch -m -- "$claim"
    unlock_claims
}
