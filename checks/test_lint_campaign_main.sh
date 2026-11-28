#!/usr/bin/env bash
# Real Git lifecycle regression: no compiler build or mock remote needed.
set -euo pipefail
SKILLS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tool="$SKILLS/scripts/lint_campaign.sh"
tmp=$(mktemp -d "${LINT_CAMPAIGN_TEST_ROOT:-${RUNNER_TEMP:-/tmp}}/lint-campaign-main.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
repo="$tmp/repo"; state="$tmp/state"
git init --quiet --bare -b campaign "$tmp/origin.git"
git init --quiet -b campaign "$repo"
git -C "$repo" config user.name 'Campaign test'
git -C "$repo" config user.email 'campaign@example.invalid'
git -C "$repo" remote add origin "$tmp/origin.git"
printf 'initial\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -qm initial
git -C "$repo" push -q origin campaign
printf '[{"id":"1","title":"Test","depends":[],"paths":["README.md"]}]\n' > "$tmp/issues.json"
(cd "$repo"; bash "$tool" init-issues "$state" campaign "$tmp/worktrees" "$tmp/issues.json")
run() { bash "$tool" "$1" "$state" "${@:2}"; }
id=$(jq -er .id "$state/config.json")
old_registry=$(jq -er .registry "$state/config.json")
run claim-issue active 1 >/dev/null
active=$(jq -er .branch "$state/claims/active.json")
run checkpoint active
base=$(git -C "$repo" rev-parse HEAD)
arch="lint-campaign/${id:0:12}/abandoned"
merged="lint-campaign/${id:0:12}/merged"
sha=$(printf 'abandoned alternative\n' | git -C "$repo" commit-tree "$base^{tree}" -p "$base")
git -C "$repo" push -q origin "$sha:refs/heads/$arch" "$base:refs/heads/$merged" "$base:refs/heads/main"
git --git-dir="$tmp/origin.git" symbolic-ref HEAD refs/heads/main
touch "$state/migrating"
run retarget main
[[ $(jq -er .id "$state/config.json") == "$id" ]]
[[ ! -e "$old_registry" && -e $(jq -er .registry "$state/config.json") ]]
[[ $(jq -er .target "$state/config.json") == main ]]
[[ $(jq -er .branch "$state/claims/active.json") == "$active" ]]
run status >/dev/null
run gc campaign
refs=$(git -C "$repo" ls-remote --heads origin)
for removed in "$arch" "$merged" campaign; do
    if rg -q -F "refs/heads/$removed" <<< "$refs"; then echo "obsolete ref survived: $removed" >&2; exit 1; fi
done
rg -q -F "refs/heads/$active" <<< "$refs"
archive=$(git -C "$repo" rev-parse origin/archive/campaign-checkpoints)
git -C "$repo" merge-base --is-ancestor "$sha" "$archive"
git -C "$repo" show "$archive:checkpoints.tsv" | rg -q -F "$arch"
run gc
[[ $(git -C "$repo" rev-parse origin/archive/campaign-checkpoints) == "$archive" ]]
printf 'Direct-main campaign lifecycle passed\n'
