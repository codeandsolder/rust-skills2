# Sourced by lint_campaign.sh. Campaign ref collection is independent of
# validation and never removes a checkpoint unless main or a durable archive
# contains it. An archive is evidence, not an integration target.
# shellcheck shell=bash
campaign_active_refs() {
    {
        issue_claims | jq -r '.[]|[.branch,.cleanup_refs[]?][]|select(.!=null)'
        queue_records | jq -r '.[]|select(.status=="staging" or .status=="pending" or .status=="running" or .status=="failed")|[.branch,.queue_branch,.cleanup_refs[]?][]|select(.!=null)'
    } | sort -u
}
campaign_pr_refs() {
    local remote slug
    remote=$(git_repo remote get-url origin)
    case "$remote" in
        https://github.com/*) slug=${remote#https://github.com/} ;;
        git@github.com:*) slug=${remote#git@github.com:} ;;
        *) return 0 ;;
    esac
    gh pr list -R "${slug%.git}" --state open --limit 500 --json headRefName --jq '.[].headRefName'
}
# Explicit extra branches are for coordinator-reviewed historical references.
# Ordinary sweeps only collect the namespace owned by this campaign.
reconcile_campaign_refs() (
    local tip archive_ref archive_tip archive_remote archive_local archive_sha archive_tree blob ref branch sha line local_sha gc_fd
    local protected remote_snapshot archive_manifest changed=false
    local -a parents=() deletions=() leases=() local_refs=() extras=("$@")
    local -A seen=() remote_refs=() eligible=() selected=() protected_refs=()
    [[ "$direct_default" == true ]] || die "ref collection requires a default-target campaign"
    exec {gc_fd}>"$state/lifecycle.lock"; flock -n "$gc_fd" || die "lifecycle reconciliation already running"
    tip=$(remote_tip)
    archive_ref=refs/heads/archive/campaign-checkpoints
    remote_snapshot=$(git_repo ls-remote --heads origin)
    protected=$(campaign_active_refs && campaign_pr_refs) || die "cannot inspect active branches"
    while IFS= read -r branch; do [[ -z "$branch" ]] || protected_refs["$branch"]=1; done <<<"$protected"
    for branch in "${extras[@]}"; do
        git check-ref-format "refs/heads/$branch" >/dev/null || die "invalid explicit branch: $branch"
        [[ "$branch" != "$target" && "refs/heads/$branch" != "$archive_ref" ]] || die "cannot collect target/archive"
        selected["$branch"]=1
    done
    archive_tip=''
    while IFS=$'\t' read -r sha ref; do
        [[ -n "$sha" && -n "$ref" ]] || continue
        branch=${ref#refs/heads/}
        if [[ "$ref" == "$archive_ref" ]]; then archive_tip=$sha; continue; fi
        [[ "$branch" == "lint-campaign/${id:0:12}/"* || -n ${selected[$branch]:-} ]] || continue
        [[ -z ${protected_refs[$branch]:-} && "$branch" != "$target" ]] || continue
        remote_refs["$branch"]=$sha
        git_repo cat-file -e "$sha^{commit}" 2>/dev/null || git_repo fetch --quiet --no-tags origin "$ref"
        git_repo cat-file -e "$sha^{commit}" || die "checkpoint unavailable: $branch"
        eligible["$branch"]=$sha
    done <<<"$remote_snapshot"
    # Also preserve committed local-only checkpoints before removing clean
    # expired worktrees. Dirty worktrees are retained, never force-removed.
    while IFS=$'\t' read -r sha ref; do
        branch=${ref#refs/heads/}
        [[ -z ${protected_refs[$branch]:-} ]] || continue
        local_refs+=("$branch")
        if [[ -z ${eligible[$branch]:-} || ${eligible[$branch]} != "$sha" ]]; then
            eligible["$branch@local"]=$sha
        fi
    done < <(git_repo for-each-ref --format='%(objectname)%09%(refname)' "refs/heads/lint-campaign/${id:0:12}/")
    archive_remote=$archive_tip
    archive_local=$(git_repo rev-parse --verify "$archive_ref" 2>/dev/null || true)
    if [[ -n "$archive_tip" ]]; then
        git_repo cat-file -e "$archive_tip^{commit}" 2>/dev/null || git_repo fetch --quiet --no-tags origin "$archive_ref"
        if [[ -n "$archive_local" ]] && git_repo merge-base --is-ancestor "$archive_tip" "$archive_local"; then archive_tip=$archive_local; fi
    elif [[ -n "$archive_local" ]]; then
        archive_tip=$archive_local
    fi
    archive_manifest=''
    if [[ -n "$archive_tip" ]]; then
        archive_manifest=$(git_repo show "$archive_tip:checkpoints.tsv") || die "archive has no checkpoint manifest"
        parents+=( -p "$archive_tip" ); seen["$archive_tip"]=1
    fi
    for branch in "${!eligible[@]}"; do
        sha=${eligible[$branch]}
        if git_repo merge-base --is-ancestor "$sha" "$tip"; then continue; fi
        if [[ -n "$archive_tip" ]] && git_repo merge-base --is-ancestor "$sha" "$archive_tip"; then continue; fi
        if [[ -z ${seen[$sha]:-} ]]; then parents+=( -p "$sha" ); seen["$sha"]=1; fi
        line=$(printf '%s\t%s' "$sha" "$branch")
        archive_manifest+=$'\n'"$line"
        changed=true
    done
    archive_sha=$archive_tip
    if [[ "$changed" == true ]]; then
        blob=$(printf '%s\n' "$archive_manifest" | sed '/^$/d' | sort -u | git_repo hash-object -w --stdin)
        archive_tree=$(printf '100644 blob %s\tcheckpoints.tsv\n' "$blob" | git_repo mktree)
        archive_sha=$(printf '%s\n' 'Archive superseded campaign checkpoints without merging rejected alternatives' | git_repo commit-tree "$archive_tree" "${parents[@]}")
        git_repo update-ref "$archive_ref" "$archive_sha" "${archive_local:-0000000000000000000000000000000000000000}"
    fi
    # Publish the single recovery reference before deleting any divergent
    # remote checkpoints, including a prior locally retained archive.
    if [[ -n "$archive_sha" ]]; then
        if [[ "$archive_sha" != "$archive_remote" ]] && ! git_repo push origin "$archive_sha:$archive_ref"; then
            say "archive publication failed; divergent checkpoints retained"
            archive_sha=''
        else
            say "checkpoint archive: $archive_sha"
        fi
    fi
    lock_claims
    protected=$(campaign_active_refs && campaign_pr_refs) || die "cannot recheck active branches"
    protected_refs=()
    while IFS= read -r branch; do [[ -z "$branch" ]] || protected_refs["$branch"]=1; done <<<"$protected"
    for branch in "${!remote_refs[@]}"; do
        sha=${remote_refs[$branch]}
        [[ -z ${protected_refs[$branch]:-} ]] || continue
        if git_repo merge-base --is-ancestor "$sha" "$tip" || { [[ -n "$archive_sha" ]] && git_repo merge-base --is-ancestor "$sha" "$archive_sha"; }; then
            ref="refs/heads/$branch"
            leases+=("--force-with-lease=$ref:$sha")
            deletions+=(":$ref")
        fi
    done
    if ((${#deletions[@]})); then
        git_repo push --atomic "${leases[@]}" origin "${deletions[@]}" || die "branch deletion raced; retry collection"
        say "removed ${#deletions[@]} obsolete remote refs"
    fi
    # Remove only clean worktrees with an exact branch match. Retain every
    # dirty checkout and every unarchived local revision for worker recovery.
    local path current record
    shopt -s nullglob
    for record in "$state/expired/"*.json; do
        branch=$(jq -er .branch "$record"); path=$(jq -er .worktree "$record")
        [[ -z ${protected_refs[$branch]:-} && -d "$path" && "$path" == "$workroot/"* ]] || continue
        current=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || true)
        [[ "$current" == "$branch" ]] || continue
        local_sha=$(git -C "$path" rev-parse HEAD)
        if git_repo merge-base --is-ancestor "$local_sha" "$tip" || { [[ -n "$archive_sha" ]] && git_repo merge-base --is-ancestor "$local_sha" "$archive_sha"; }; then
            [[ -z $(git -C "$path" status --porcelain --untracked-files=all) ]] || continue
            git_repo worktree remove "$path" || continue
            git_repo update-ref -d "refs/heads/$branch" "$local_sha" || true
        fi
    done
    for branch in "${local_refs[@]}"; do
        [[ -z ${protected_refs[$branch]:-} ]] || continue
        local_sha=$(git_repo rev-parse --verify "refs/heads/$branch" 2>/dev/null || true)
        [[ -n "$local_sha" ]] || continue
        # Git branch -d would compare against a potentially unrelated HEAD;
        # explicit ancestry and checked-out-branch protection are stronger.
        if git_repo worktree list --porcelain | rg -Fxq "branch refs/heads/$branch"; then continue; fi
        if git_repo merge-base --is-ancestor "$local_sha" "$tip" || { [[ -n "$archive_sha" ]] && git_repo merge-base --is-ancestor "$local_sha" "$archive_sha"; }; then
            git_repo update-ref -d "refs/heads/$branch" "$local_sha" || true
        fi
    done
    unlock_claims
    git_repo fetch --quiet --prune origin
)
