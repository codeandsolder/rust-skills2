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
printf "worker change\n" >> "$tmp/worktrees/active/README.md"
git -C "$tmp/worktrees/active" commit -qam worker
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
    if [[ $'\n'"$refs"$'\n' == *$'\t'"refs/heads/$removed"$'\n'* ]]; then echo "obsolete ref survived: $removed" >&2; exit 1; fi
done
[[ $'\n'"$refs"$'\n' == *$'\t'"refs/heads/$active"$'\n'* ]]
archive=$(git -C "$repo" rev-parse origin/archive/campaign-checkpoints)
git -C "$repo" merge-base --is-ancestor "$sha" "$archive"
manifest=$(git -C "$repo" show "$archive:checkpoints.tsv")
[[ $'\n'"$manifest"$'\n' == *$'\t'"$arch"$'\n'* ]]
run gc
[[ $(git -C "$repo" rev-parse origin/archive/campaign-checkpoints) == "$archive" ]]
# A direct-main issue can be published with focused evidence even if the
# project has no Rust workspace at all; the canonical hosted gate owns global
# policy. A failed focused command must still retain the submission.
# Collection must also run before a busy queue's next validation, not
# only after the queue is empty. The running submission stays protected.
busy="lint-campaign/${id:0:12}/busy-abandoned"
git -C "$repo" push -q origin "$sha:refs/heads/$busy"
rm -f -- "$state/lifecycle-last"
run publish active "test -z \"\$(git ls-remote --heads origin refs/heads/$busy)\" && touch \"$tmp/collected-before-validation\"; false"
run drain
[[ -f "$tmp/collected-before-validation" ]]
[[ $(jq -er .status "$state/queue/000000001.json") == failed ]]
[[ -n $(git -C "$repo" ls-remote --heads origin "refs/heads/$active") ]]
run recover 000000001 active
run publish active 'test -f README.md'
# Simulate an out-of-band invalid manifest: preserve the pending queue and
# report failure from a one-shot drain. A serving validator must retry.
cp "$state/issues.json" "$tmp/valid-manifest.json"
jq '.[0].depends = ["999"]' "$state/issues.json" > "$state/issues.json.tmp"
mv "$state/issues.json.tmp" "$state/issues.json"
if run drain > "$tmp/drain.log" 2>&1; then
    echo 'invalid manifest unexpectedly drained' >&2; exit 1
fi
grep -q 'cannot schedule validation' "$tmp/drain.log"
[[ $(jq -er .status "$state/queue/000000002.json") == pending ]]
mkdir "$tmp/caller"
(cd "$tmp/caller"; run serve) > "$tmp/serve.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT
for _ in {1..100}; do
    if grep -q 'cannot schedule validation' "$tmp/serve.log"; then break; fi
    kill -0 "$server"
    sleep 0.1
done
grep -q 'cannot schedule validation' "$tmp/serve.log"
rmdir "$tmp/caller"
mv "$tmp/valid-manifest.json" "$state/issues.json"
for _ in {1..200}; do
    if [[ $(jq -er .status "$state/queue/000000002.json") == published ]]; then break; fi
    kill -0 "$server"
    sleep 0.1
done
touch "$state/migrating"
wait "$server"
trap 'rm -rf -- "$tmp"' EXIT
[[ $(jq -er .status "$state/queue/000000002.json") == published ]]
! grep -q 'error retrieving current directory' "$tmp/serve.log"
[[ $(git -C "$repo" show origin/main:README.md) == $'initial\nworker change' ]]
printf 'Direct-main campaign lifecycle passed\n'
