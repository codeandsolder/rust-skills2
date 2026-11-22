#!/usr/bin/env bash
# Real Git + Cargo integration test. No mock merge or diagnostics.
set -euo pipefail
SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$SKILLS/scripts/lint_campaign.sh"
bash "$SKILLS/checks/test_lint_campaign_leases.sh"
bash "$SKILLS/checks/test_lint_campaign_priority.sh"
tmp=$(mktemp -d "${LINT_CAMPAIGN_TEST_ROOT:-${RUNNER_TEMP:-/tmp}}/lint-campaign-test.XXXXXX")
cleanup() {
    local rc=$?
    if ((rc!=0)); then
        find "$tmp" -type f \( -name '*.stderr' -o -name 'queue-*.log' -o -name '*.gate.log' -o -name 'drain.log' \) -print |
            while IFS= read -r log; do printf '\n== %s ==\n' "$log"; tail -40 "$log"; done
    fi
    rm -rf -- "$tmp"
}
trap cleanup EXIT
export LINT_CAMPAIGN_NIGHTLY=nightly
export RUST_SKILLS2_ALLOW_TEST_PANICS=true
# Deliberately supply an undersized inherited value: the campaign must clamp it.
export CARGO_BUILD_JOBS=1
git init --quiet --bare "$tmp/origin.git"
git init --quiet -b campaign "$tmp/repo"
git -C "$tmp/repo" config user.name "Lint campaign test"
git -C "$tmp/repo" config user.email "test@example.invalid"
git -C "$tmp/repo" remote add origin "$tmp/origin.git"
mkdir "$tmp/repo/src" "$tmp/repo/tests" "$tmp/repo/shared"
cat >"$tmp/repo/Cargo.toml" <<'TOML'
[package]
name = "campaign-fixture"
version = "0.0.0"
edition = "2024"
publish = false
TOML
cat >"$tmp/repo/src/lib.rs" <<'RS'
mod alpha;
mod gamma;
#[path = "../shared/beta.rs"]
mod beta;
pub use alpha::ALPHA;
pub use beta::BETA;
pub use gamma::GAMMA;
RS
printf 'pub const ALPHA: u32 = 123456;\n' >"$tmp/repo/src/alpha.rs"
printf 'pub const BETA: u32 = 234567;\n' >"$tmp/repo/shared/beta.rs"
printf 'pub const GAMMA: u32 = 345678;\n' >"$tmp/repo/src/gamma.rs"
cat >"$tmp/repo/tests/relaxed.rs" <<'RS'
#[test]
fn relaxed() {
    let value: u32 = "123456".parse().unwrap();
    assert_eq!(value, 123456);
}
RS
(
    cd "$tmp/repo"
    cargo +nightly generate-lockfile --offline
    cargo +nightly fmt --all
    git add .
    git commit --quiet -m baseline
    git push --quiet -u origin campaign
    bash "$tool" init "$tmp/state" campaign "$tmp/worktrees" 'test "$CARGO_BUILD_JOBS" -eq 16 && cargo +nightly test --locked'
)
state="$tmp/state"
run() { bash "$tool" "$1" "$state" "${@:2}"; }
# The ordinary deny-level final gate must reject inherited lint debt even
# though the inventory succeeds. The relaxed integration test is not a shard.
baseline=$(jq -er .base "$state/config.json")
[[ "$(jq length "$state/inventory/$baseline.json")" == 3 ]]
# A campaign can adopt a shared isolated Rustup home without changing
# its baseline. The fixture links the current test toolchains (no updates).
host=$(rustc +nightly -vV | sed -n 's/^host: //p')
pinned="$tmp/pinned-rustup"
mkdir -p "$pinned/toolchains"
for channel in nightly; do
    compiler=$(rustup which --toolchain "$channel" rustc)
    ln -s "$(dirname "$(dirname "$compiler")")" "$pinned/toolchains/$channel-$host"
done
if run upgrade "$pinned"; then echo "unpaused migration accepted" >&2; exit 1; fi
touch "$state/migrating"
if run upgrade "$tmp/absent"; then echo "missing Rustup home accepted" >&2; exit 1; fi
[[ -e "$state/migrating" ]]
run upgrade "$pinned"
[[ "$(jq -r .rustup_home "$state/config.json")" == "$pinned" ]]
[[ ! -e "$state/migrating" ]]
[[ "$(jq length "$state/inventory/$baseline.json")" == 3 ]]
# An invalid caller Rustup home must not override the campaign selection.
RUSTUP_HOME="$tmp/absent" run status >/dev/null
if run finish true; then echo "strict finish accepted outstanding lints" >&2; exit 1; fi
# Claim concurrently; the claims must have disjoint exact paths.
RUSTUP_HOME="$tmp/absent" run claim one 1 "" 1 >"$tmp/one.log" &
one_pid=$!
run claim two 1 "" 1 >"$tmp/two.log" &
two_pid=$!
wait "$one_pid"
wait "$two_pid"
one_file=$(jq -er '.files[0]' "$state/claims/one.json")
two_file=$(jq -er '.files[0]' "$state/claims/two.json")
[[ "$one_file" != "$two_file" ]]
[[ "$one_file" == shared/beta.rs || "$two_file" == shared/beta.rs ]]
if run extend one "$two_file"; then echo "overlap accepted" >&2; exit 1; fi
if run finish; then echo "finish accepted claims" >&2; exit 1; fi
run defer two "test deferral"
if run claim deferred 1 "$two_file" 1; then echo "deferral ignored" >&2; exit 1; fi
run retry "$two_file"
run claim two 1 "$two_file" 1 >"$tmp/two-again.log"
one="$tmp/worktrees/one"
printf '// outside scope\n' >>"$one/$two_file"
git -C "$one" add "$two_file"
git -C "$one" commit --quiet -m outside-scope
if run publish one; then echo "outside scope accepted" >&2; exit 1; fi
git -C "$one" reset --quiet --hard HEAD^
for worker in one two; do
    checkout="$tmp/worktrees/$worker"
    file=$(jq -er '.files[0]' "$state/claims/$worker.json")
    sed -i -e 's/123456/123_456/' -e 's/234567/234_567/' "$checkout/$file"
    git -C "$checkout" add "$file"
    git -C "$checkout" commit --quiet -m "fix $file"
    run checkpoint "$worker"
done
# Submissions return before any compilation and retain their reservations.
reuse_check=$(cat <<'SH'
test "$CARGO_BUILD_BUILD_DIR" = "$CARGO_TARGET_DIR"
cargo +nightly test --locked --lib --no-run --message-format=json | jq -se 'any(.[]; .reason=="compiler-artifact" and .fresh==true and .profile.test==true and (.target.kind|index("lib"))!=null)'
SH
)
run publish one "$reuse_check
touch '$tmp/validation-started'; while ! test -e '$tmp/release-validation'; do sleep 0.1; done"
run publish two
[[ "$(git -C "$tmp/repo" ls-remote --heads origin campaign | cut -f1)" == "$baseline" ]]
[[ "$(jq -rs '[.[]|select(.status=="pending")]|length' "$state"/queue/*.json)" == 2 ]]
if run claim other 1 "$one_file" 1; then echo "queued file claimed" >&2; exit 1; fi
run drain >"$tmp/drain.log" 2>&1 &
drain_pid=$!
# While the first validator is running, the same editor can claim fresh files.
for ((i=0;i<1800;i++)); do
    [[ -e "$tmp/validation-started" ]] && break
    if ! kill -0 "$drain_pid" 2>/dev/null; then cat "$tmp/drain.log"; exit 1; fi
    sleep 0.1
done
[[ -e "$tmp/validation-started" ]] || { cat "$tmp/drain.log"; touch "$tmp/release-validation"; exit 1; }
if run drain; then echo "second validator started" >&2; touch "$tmp/release-validation"; exit 1; fi
run claim one 1 src/gamma.rs 1 >"$tmp/next-claim.log"
[[ "$(jq -r .status "$state/queue/000000001.json")" == running ]]
[[ "$(jq -r .status "$state/queue/000000002.json")" == pending ]]
if run extend one "$two_file"; then echo "queued overlap accepted" >&2; touch "$tmp/release-validation"; exit 1; fi
touch "$tmp/release-validation"
wait "$drain_pid" || { cat "$tmp/drain.log"; exit 1; }
[[ "$(jq -rs '[.[]|select(.status=="published")]|length' "$state"/queue/*.json)" == 2 ]]
[[ ! -e "$state/build/validator" ]]
# Failure retains the source and reservation, but never blocks later jobs.
one="$tmp/worktrees/one"
printf '// no reduction\n' >>"$one/src/gamma.rs"
git -C "$one" add src/gamma.rs
git -C "$one" commit --quiet -m no-reduction
run publish one
run drain
[[ "$(jq -r .status "$state/queue/000000003.json")" == failed ]]
[[ ! -e "$state/build/validator" ]]
run recover 000000003 one
sed -i 's/345678/345_678/' "$one/src/gamma.rs"
git -C "$one" add src/gamma.rs
git -C "$one" commit --quiet -m fix-gamma
run publish one false
run drain
[[ "$(jq -r .status "$state/queue/000000004.json")" == failed ]]
run recover 000000004 one
run publish one
run drain
[[ "$(jq -r .status "$state/queue/000000005.json")" == published ]]
git -C "$tmp/repo" fetch --quiet origin
tip=$(git -C "$tmp/repo" rev-parse origin/campaign)
[[ "$(jq length "$state/inventory/$tip.json")" == 0 ]]
[[ "$(git -C "$tmp/repo" show "$tip:src/alpha.rs")" == 'pub const ALPHA: u32 = 123_456;' ]]
[[ "$(git -C "$tmp/repo" show "$tip:shared/beta.rs")" == 'pub const BETA: u32 = 234_567;' ]]
[[ -z "$(git -C "$tmp/repo" ls-remote --heads origin 'refs/heads/lint-campaign/*')" ]]
[[ -z "$(find "$state/claims" -name '*.json' -print -quit)" ]]
run finish 'cargo +nightly test --locked'
[[ "$(cat "$state/finished")" == "$tip" ]]
[[ -z "$(find "$tmp/worktrees" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]
if run claim after-finish; then echo "unexpected success" >&2; exit 1; fi
printf 'Serialized lint campaign integration test passed.\n'

cat >"$tmp/issues.json" <<'JSON'
[
    {"id":"101","title":"Refactor alpha","depends":[],"paths":["src/alpha.rs","NOTES.md"]},
    {"id":"102","title":"Refactor beta","depends":[],"paths":["shared/"]},
    {"id":"103","title":"Follow alpha","depends":["101"],"paths":["src/alpha.rs"]},
    {"id":"104","title":"Join both results","depends":["102","103"],"paths":["src/gamma.rs"]}
]
JSON
state="$tmp/issue-state"
(
    cd "$tmp/repo"
    bash "$tool" init-issues "$state" campaign "$tmp/issue-worktrees" "$tmp/issues.json" 'cargo +nightly test --locked'
)
[[ "$(run issues | jq -r 'map(.status)|join(",")')" == 'ready,ready,blocked,blocked' ]]
run claim-issue one 101
run claim-issue two 102
if run claim-issue other 103; then echo "dependency bypass" >&2; exit 1; fi
run extend two src/alpha.rs
one="$tmp/issue-worktrees/one"
two="$tmp/issue-worktrees/two"
printf '# Refactor notes\n' >"$one/NOTES.md"
printf '// Refactor alpha.\n' >>"$one/src/alpha.rs"
git -C "$one" add NOTES.md src/alpha.rs
git -C "$one" commit --quiet -m 'refactor alpha'
if run publish one; then echo "missing focused gate accepted" >&2; exit 1; fi
if run publish one 'cargo +stable test --locked'; then echo "stable submission accepted" >&2; exit 1; fi
run publish one 'cargo +nightly test --locked'
# Exercise the one-time migration of a legacy live queue, not a compatibility
# execution path. Keep original command and toolchain metadata for audit.
jq '.stable="stable" | .stable_version="legacy" | .smoke="cargo +stable test --locked"' "$state/config.json" >"$state/config.tmp"
mv "$state/config.tmp" "$state/config.json"
jq '.focused="cargo +stable test --locked"' "$state/queue/000000001.json" >"$state/queue/000000001.tmp"
mv "$state/queue/000000001.tmp" "$state/queue/000000001.json"
if run upgrade; then echo "unpaused compiler migration accepted" >&2; exit 1; fi
touch "$state/migrating"
run upgrade
jq -e 'has("stable")|not' "$state/config.json"
jq -e '.smoke=="cargo +nightly test --locked"' "$state/config.json"
jq -e '.focused=="cargo +nightly test --locked"' "$state/queue/000000001.json"
jq -e '.focused=="cargo +stable test --locked"' "$state/migrations/nightly-only/queue/000000001.json"
if run claim-issue other 103; then echo "pending dependency accepted" >&2; exit 1; fi
printf '// Refactor beta.\n' >>"$two/shared/beta.rs"
git -C "$two" add shared/beta.rs
git -C "$two" commit --quiet -m 'refactor beta'
run publish two false
run drain
[[ "$(run issues | jq -r 'map(.status)|join(",")')" == 'published,failed,ready,blocked' ]]
run recover 000000002 two
[[ "$(jq -r .issue "$state/claims/two.json")" == 102 ]]
run publish two 'cargo +nightly test --locked'
run drain
run claim-issue one
[[ "$(jq -r .issue "$state/claims/one.json")" == 103 ]]
# An issue cannot introduce strict debt even when its focused tests would pass.
sed -i 's/123_456/123456/' "$one/src/alpha.rs"
git -C "$one" add src/alpha.rs
git -C "$one" commit --quiet -m 'introduce lint regression'
run publish one 'cargo +nightly test --locked'
run drain
[[ "$(run issues | jq -r 'map(.status)|join(",")')" == 'published,published,failed,blocked' ]]
run recover 000000004 one
sed -i 's/123456/123_456/' "$one/src/alpha.rs"
printf '// Follow-up alpha.\n' >>"$one/src/alpha.rs"
git -C "$one" add src/alpha.rs
git -C "$one" commit --quiet -m 'finish follow-up alpha'
run publish one 'cargo +nightly test --locked'
run drain
if run finish true; then echo "finish accepted incomplete issues" >&2; exit 1; fi
run claim-issue one
[[ "$(jq -r .issue "$state/claims/one.json")" == 104 ]]
run extend one docs/example.md
mkdir -p "$one/docs"
printf '# Combined result\n' >"$one/docs/example.md"
git -C "$one" add docs/example.md
git -C "$one" commit --quiet -m 'document combined result'
run publish one 'cargo +nightly test --locked'
run drain
[[ "$(run issues | jq -r 'map(.status)|join(",")')" == 'published,published,published,published' ]]
# Amend a live manifest; preserve completed records and reject bad DAGs.
jq '. + [{"id":"105","title":"Concurrent alpha one","depends":[],"paths":["src/alpha.rs"]},
         {"id":"106","title":"Concurrent alpha two","depends":[],"paths":["src/alpha.rs"]}]' "$tmp/issues.json" >"$tmp/expanded.json"
run amend-issues "$tmp/expanded.json"
if run amend-issues "$tmp/issues.json"; then echo "removed issue accepted" >&2; exit 1; fi
jq '.[0].title="changed started issue"' "$tmp/expanded.json" >"$tmp/invalid.json"
if run amend-issues "$tmp/invalid.json"; then echo "changed started issue accepted" >&2; exit 1; fi
jq '.[5].depends=["999"]' "$tmp/expanded.json" >"$tmp/invalid.json"
if run amend-issues "$tmp/invalid.json"; then echo "invalid dependency accepted" >&2; exit 1; fi
run claim-issue one 105
run claim-issue two 106
if run claim-issue other 105; then echo "duplicate issue claim accepted" >&2; exit 1; fi
grep -q '123_456' "$one/src/alpha.rs"
sed -i 's/123_456/123_457/' "$one/src/alpha.rs"
sed -i 's/123_456/123_458/' "$two/src/alpha.rs"
for checkout in "$one" "$two"; do
    git -C "$checkout" add src/alpha.rs
    git -C "$checkout" commit --quiet -m 'overlapping alpha edit'
done
run publish one 'cargo +nightly test --locked'
run publish two 'cargo +nightly test --locked'
run drain
[[ "$(jq -r .status "$state/queue/000000007.json")" == published ]]
[[ "$(jq -r .status "$state/queue/000000008.json")" == failed ]]
jq -e '.paths==["src/alpha.rs"]' "$state/logs/queue-000000008.conflict.json"
run recover 000000008 two
[[ "$(git -C "$two" diff --name-only --diff-filter=U)" == src/alpha.rs ]]
printf 'pub const ALPHA: u32 = 123_459;\n// Refactor alpha.\n// Follow-up alpha.\n' >"$two/src/alpha.rs"
git -C "$two" add src/alpha.rs
git -C "$two" commit --quiet --no-edit
run publish two 'cargo +nightly test --locked'
run drain
[[ "$(run issues | jq -r 'map(.status)|join(",")')" == 'published,published,published,published,published,published' ]]
run finish 'cargo +nightly test --locked'
printf 'Dependency-aware issue campaign integration test passed.\n'
