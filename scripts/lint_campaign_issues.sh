# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state belongs to the calling campaign.
# Issue-driven selection uses the existing durable queue/claims/validator.
# Ordered DAG; started tasks retain their definitions.
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
# Files define edit scope, not exclusion. Overlap is advisory in issue mode.
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
    chosen=$(jq -c --arg id "$request" '[.[] | select(.status=="ready" and ($id=="" or .id==$id))] | (map(select(.conflicts|length==0))[0] // .[0] // empty)' <<<"$plan")
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
    jq 'del(.files,.waiting_for,.status)' <<<"$chosen"
}

require_finished_issues() {
    if [[ -f "$state/issues.json" ]]; then
        jq -e --slurpfile raw_queue <(queue_records) '
          [$raw_queue[0][] | select(.status=="published") | .issue] as $done |
          ([.[].id] - $done | length == 0)
        ' "$state/issues.json" >/dev/null || die "unpublished issues remain"
    fi
}

# Atomic replacement; retain all IDs and definitions of started tasks.
amend_issues() (
    local input=$1 staged digest manifest
    check_tools
    [[ -f "$state/issues.json" ]] || die "not an issue campaign"
    staged=$(mktemp "$state/.issues.XXXXXX")
    trap 'rm -f -- "$staged"' EXIT
    cp -- "$input" "$staged"
    validate_issue_manifest "$staged"
    lock_claims
    [[ -f "$registry" && "$(cat "$registry")" == "$state" ]] || die "campaign closed during amendment"
    [[ ! -e "$state/migrating" ]] || die "campaign migration in progress"
    jq -e --slurpfile old "$state/issues.json" \
        --slurpfile claims <(issue_claims) --slurpfile queue <(queue_records) '
      . as $new |
      ($old[0] | map({key:.id,value:.}) | from_entries) as $before |
      ($new | map({key:.id,value:.}) | from_entries) as $after |
      ([$claims[0][].issue, $queue[0][].issue] | map(select(. != null)) | unique) as $started |
      if (($before|keys) - ($after|keys) | length) != 0 then error("cannot remove existing issues")
      elif any($started[]; $before[.] != $after[.]) then error("cannot redefine started issues")
      else true end
    ' "$staged" >/dev/null || die "invalid live issue amendment"
    mkdir -p "$state/manifests"
    for manifest in "$state/issues.json" "$staged"; do
        digest=$(git_repo hash-object "$manifest")
        if [[ ! -f "$state/manifests/$digest.json" ]]; then
            cp -- "$manifest" "$state/manifests/$digest.json"
        fi
    done
    mv -- "$staged" "$state/issues.json"
    unlock_claims
    say "amended issue manifest to $(jq length "$state/issues.json") tasks; history $state/manifests"
)
