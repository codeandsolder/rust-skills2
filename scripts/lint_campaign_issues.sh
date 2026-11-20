# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state belongs to the calling campaign.
# Issue-driven selection uses the existing durable queue/claims/validator.
# The manifest is immutable for a campaign; an ordered DAG of issue tasks.
validate_issue_manifest() {
    local manifest=$1 path
    jq -e '
      type == "array" and length > 0 and
      all(.[]; (.id | type == "string" and test("^[1-9][0-9]*$")) and
          (.title | type == "string" and length > 0) and
          (.depends | type == "array" and all(.[]; type == "string")) and
          (.paths | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))) and
      ([.[].id] | length == (unique | length)) and
      (reduce .[] as $task ({seen:[],valid:true};
          .valid = (.valid and (($task.depends - .seen) | length == 0)) |
          .seen += [$task.id]) | .valid)
    ' "$manifest" >/dev/null || die "issue manifest must be an ordered, unique, acyclic task list"
    while IFS= read -r path; do
        valid_repo_path "${path%/}"
    done < <(jq -r '.[].paths[]' "$manifest")
}

issue_claims() {
    local -a records
    shopt -s nullglob
    records=("$state/claims/"*.json)
    if (("${#records[@]}")); then jq -s '.' "${records[@]}"; else printf '[]\n'; fi
}

# Caller holds claims.lock. Expand directory scopes at the actual target tip.
# Paths are materialized as exact file reservations, so extend/publish use
# precisely the same conflict checks and scope validation as lint workers.
issue_status() {
    local tip=$1
    jq -n --slurpfile tasks "$state/issues.json" \
        --slurpfile raw_tracked <(git_repo ls-tree -r --name-only -z "$tip" |
            jq -Rs 'split("\u0000") | map(select(length>0))') \
        --slurpfile raw_claims <(issue_claims) --slurpfile raw_queue <(queue_records) '
      def scope($task; $tracked):
        [$task.paths[] as $path |
          if ($path | endswith("/"))
          then $tracked[] | select(startswith($path))
          else $path end] | unique;
      $raw_tracked[0] as $tracked | $raw_claims[0] as $claims | $raw_queue[0] as $queue |
      [$queue[] | select(.status=="published") | .issue] as $done |
      ($claims + [$queue[] | select(.status=="staging" or .status=="pending" or .status=="running" or .status=="failed")]) as $busy |
      [$busy[].files[]] as $occupied |
      $tasks[0] | map(
        . as $task | scope($task; $tracked) as $files |
        ($task.depends - $done) as $missing |
        [$files[] | select(. as $f | $occupied | index($f))] as $conflicts |
        [$busy[] | select(.issue==$task.id)] as $own |
        . + {files:$files,waiting_for:$missing,conflicts:$conflicts,
             status:(if ($done|index($task.id)) != null then "published"
               elif ($own|length)>0 then ($own[0].status // "claimed")
               elif ($missing|length)>0 then "blocked"
               elif ($conflicts|length)>0 then "reserved"
               elif ($files|length)==0 then "empty-scope"
               else "ready" end)})
    '
}

claim_issue() {
    local request=${1:-} tip i plan chosen issue title files topic path
    worker=$2
    lock_worker
    check_tools
    [[ -f "$state/issues.json" ]] || die "not an issue campaign"
    for i in 1 2 3 4; do
        tip=$(remote_tip)
        [[ -f "$state/inventory/$tip.json" ]] || die "target inventory not cached yet"
        [[ "$(jq length "$state/inventory/$tip.json")" == 0 ]] || die "issue campaign target has strict debt"
        lock_claims
        [[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign closed during claim"
        [[ "$(git_repo rev-parse "refs/remotes/origin/$target")" != "$tip" ]] || break
        unlock_claims
        [[ "$i" != 4 ]] || die "target advanced; retry claim"
    done
    claim="$state/claims/$worker.json"
    [[ ! -e "$claim" ]] || die "worker already owns a claim"
    plan=$(issue_status "$tip")
    chosen=$(jq -c --arg id "$request" '[.[] | select(.status=="ready" and ($id=="" or .id==$id))][0] // empty' <<<"$plan")
    [[ -n "$chosen" ]] || die "no ready issue matching request; inspect issues"
    issue=$(jq -er .id <<<"$chosen")
    title=$(jq -er .title <<<"$chosen")
    files=$(jq -c .files <<<"$chosen")
    while IFS= read -r path; do valid_repo_path "$path"; done < <(jq -r '.[]' <<<"$files")
    topic="lint-campaign/${id:0:12}/$worker-$(date +%s%N)"
    work="$workroot/$worker"
    git_repo worktree add --quiet -b "$topic" "$work" "$tip"
    jq -n --arg worker "$worker" --arg base "$tip" --arg work "$work" --arg topic "$topic" \
        --arg issue "$issue" --arg title "$title" --argjson files "$files" \
        '{worker:$worker,base:$base,worktree:$work,branch:$topic,files:$files,issue:$issue,issue_title:$title}' >"$claim.tmp"
    mv -- "$claim.tmp" "$claim"
    unlock_claims
    cat "$claim"
    jq 'del(.files,.conflicts,.waiting_for,.status)' <<<"$chosen"
}

require_finished_issues() {
    if [[ -f "$state/issues.json" ]]; then
        jq -e --slurpfile raw_queue <(queue_records) '
          [$raw_queue[0][] | select(.status=="published") | .issue] as $done |
          ([.[].id] - $done | length == 0)
        ' "$state/issues.json" >/dev/null || die "unpublished issues remain"
    fi
}
