#!/usr/bin/env bash
# Exercise real queue files and the same selector used by drain_queue.
set -euo pipefail
SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
state=$(mktemp -d "${LINT_CAMPAIGN_TEST_ROOT:-${RUNNER_TEMP:-/tmp}}/lint-priority.XXXXXX")
trap 'rm -rf -- "$state"' EXIT
mkdir "$state/queue"
source "$SKILLS/scripts/lint_campaign_queue.sh"
job() {
    jq -n --arg job "$1" --arg issue "$2" --arg status "$3" \
        '{job:$job,issue:$issue,status:$status}' >"$state/queue/$1.json"
}
expect() {
    local actual
    actual=$(next_validation_job)
    [[ "$actual" == "$1" ]] || { printf 'expected %s, got %s\n' "$1" "$actual" >&2; exit 1; }
}
job 000000001 1 pending
job 000000002 2 pending
job 000000003 3 pending
expect 000000001
cat >"$state/issues.json" <<'JSON'
[
 {"id":"1","depends":[]},
 {"id":"2","depends":[]},
 {"id":"3","depends":[]},
 {"id":"4","depends":["2"]},
 {"id":"5","depends":["2"]},
 {"id":"6","depends":["4","5"]},
 {"id":"7","depends":["3"]},
 {"id":"8","depends":["7"]},
 {"id":"9","depends":["8"]}
]
JSON
# 2 and 3 each have three distinct descendants, despite 2's diamond.
expect 000000002
job 000000002 2 failed
expect 000000003
# A recovered high-impact submission gets its priority back.
job 000000004 2 pending
expect 000000003
job 000000003 3 failed
expect 000000004
job 000000005 4 published
job 000000006 5 published
job 000000007 6 published
# Published descendants no longer contribute.
expect 000000001
job 000000004 2 running
expect 000000004
job 000000004 2 published
job 000000001 1 published
expect ''
printf 'Dependency-priority queue tests passed.\n'
