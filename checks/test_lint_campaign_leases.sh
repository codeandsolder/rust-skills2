#!/usr/bin/env bash
# Real linked Git worktrees, clocks, files, locks and queue records.
set -euo pipefail
SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp=$(mktemp -d "${LINT_CAMPAIGN_TEST_ROOT:-${RUNNER_TEMP:-/tmp}}/lint-lease-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
state="$tmp/state"; workroot="$tmp/worktrees"; repo="$tmp/repo"
mkdir -p "$state"/{claims,locks,queue} "$workroot"
git init -q -b campaign "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
printf 'base\n' >"$repo/source"
git -C "$repo" add source
git -C "$repo" commit -qm initial
git_repo() { git -C "$repo" "$@"; }
say() { printf '%s\n' "$*" >&2; }
die() { say "$*"; exit 1; }
lock_claims() { exec {claims_fd}>"$state/claims.lock"; flock -x "$claims_fd"; }
unlock_claims() { flock -u "$claims_fd"; exec {claims_fd}>&-; }
source "$SKILLS/scripts/lint_campaign_queue.sh"
source "$SKILLS/scripts/lint_campaign_issues.sh"
source "$SKILLS/scripts/lint_campaign_leases.sh"
tip=$(git_repo rev-parse HEAD)
printf '[{"id":"1","title":"Work","depends":[],"paths":["source"]}]\n' >"$state/issues.json"
make_claim() {
    local owner=$1 branch="lint-campaign/test/$1-1" work="$workroot/$1"
    git_repo worktree add --quiet -b "$branch" "$work" "$tip"
    jq -n --arg worker "$owner" --arg worktree "$work" --arg branch "$branch" --arg base "$tip"         '{worker:$worker,worktree:$worktree,branch:$branch,base:$base,files:["source"],issue:"1"}' >"$state/claims/$owner.json"
}
make_claim one
now=$(date +%s)
lock_claims
expire_claims "$((now + 899))"
[[ -f "$state/claims/one.json" ]]
# Real worker lock wins even when the claim would otherwise expire.
exec {active_fd}>"$state/locks/one.lock"
flock -x "$active_fd"
expire_claims "$((now + 1200))"
[[ -f "$state/claims/one.json" ]]
exec {active_fd}>&-
# Recent direct worktree activity renews eligibility without scheduler use.
printf 'unpublished\n' >>"$workroot/one/source"
touch -d "@$((now + 600))" "$workroot/one/source"
expire_claims "$((now + 1200))"
[[ -f "$state/claims/one.json" ]]
touch -d "@$now" "$workroot/one/source"
# Stale dirty work is preserved, exact issue becomes available again.
expire_claims "$((now + 1200))"
[[ ! -e "$state/claims/one.json" ]]
[[ -f "$state/expired/one-1.json" ]]
grep -qx unpublished "$workroot/one/source"
[[ "$(git_repo rev-parse refs/heads/lint-campaign/test/one-1)" == "$tip" ]]
[[ "$(issue_status "$tip" | jq -r '.[0].status')" == ready ]]
[[ "$(new_worker_worktree one lint-campaign/test/one-2)" == "$workroot/one-2" ]]
unlock_claims
# A lease heartbeat updates the claim and direct edits with preserved mtime
# are recognized by ctime, even with the old claim timestamp.
make_claim two
worker=two; claim="$state/claims/two.json"
touch -d "@$((now - 1200))" "$claim"
renew_claim
[[ "$(stat -c %Y "$claim")" -ge "$now" ]]
# Staging is transferred to explicit failed recovery if its editor abandons it.
jq '. + {job:"000000001",status:"staging",source:.base}' "$claim" >"$state/queue/000000001.json"
# Neither pending nor running submissions are editor claims.
jq '.status="pending" | .job="000000002"' "$state/queue/000000001.json" >"$state/queue/000000002.json"
lock_claims
expire_claims "$((now + 1200))"
unlock_claims
[[ -f "$state/expired/two-1.json" ]]
[[ "$(jq -r .status "$state/queue/000000001.json")" == failed ]]
[[ "$(jq -r .status "$state/queue/000000002.json")" == pending ]]
printf 'Claim lease tests passed.\n'
