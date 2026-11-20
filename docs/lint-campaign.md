# Temporary parallel lint campaigns

Use this when a repository has existing strict lint debt and several agents
can work concurrently. Do not weaken its pull request gates or dedicate an
agent to merging everyone's branches. Use one temporary staging/topic branch
and a shared local checkout, preferably with a draft PR into the default
branch. The default branch is never a campaign target.

## Start once

Requirements: Bash, Git, jq, flock (Linux), uv, the installed stable/nightly
Rust tools, and the existing managed sccache wrapper. All participating agents
must use the same Git common directory on the same host and the same
rust-skills2 revision. The tool is not a distributed lease service for separate
clones. Keep that pinned rust-skills2 checkout available throughout a campaign.
Do not use a moving toolchain or modify compiler flags during a campaign.

From the **target repository**, with a published temporary branch:

```bash
tool=/absolute/path/to/rust-skills2/scripts/lint_campaign.sh
state=/absolute/external/build/lint-campaign
worktrees=/absolute/projects/repo-lint-campaign
# Both named directories must be new, disjoint, and outside any worktree.
# Match the target's actual strict-rust workflow input if it opts in:
export RUST_SKILLS2_ALLOW_TEST_PANICS=true
# RUSTC_WRAPPER already points at the managed cache; never start another.
"$tool" init "$state" chore/strict-cleanup "$worktrees" \
  'cargo +stable test --locked --lib'
```

The last argument is a required shared regression command for every
publication (defaults to full workspace tests). Choose a sufficiently
representative, affordable command; require additional focused/reference
tests for sensitive changes. The tool pins the compiler versions, policy
revision, test panic default, target and initial Git revision. Special
workspace package overrides are resolved by the normal rust-skills2 resolver.

Inventory uses the explicit diagnostic-only `scripts/strict_clippy.sh
--inventory` entry point. It shares the canonical lint list, Clippy
configuration, package/workspace test exemptions and Cargo selection rules.
Style and other inherited strict debt are reported as warnings so compilation
can continue into later targets; correctness, suspicious, performance and
unsafe-operation failures remain fatal, plus explicit suspicious-operation
grouping. The ordinary no-argument strict gate is unchanged and required at
finish. Neither the production CI workflow nor its required checks are
temporarily relaxed.

## Any number of workers

Each worker chooses a distinct ID, for example `agent-1`.

```bash
"$tool" claim "$state" agent-1 20 src/ 4
```

This assigns up to four files and approximately twenty current diagnostics.
A single file with more findings is exclusively assigned rather than partitioned
by line; altering its definitions in two worktrees is unsafe. The returned JSON
includes the worktree, topic branch and exact claimed paths, followed by
current diagnostics. An optional path prefix lets a specialist focus on a
subsystem. The state registry uses short flock critical sections for claims,
not a global build lock. Inventories are cached by commit and deduplicated by
primary source location, lint code and diagnostic message.

Work inside the returned worktree. Fix the root cause, preserve project
semantics, add regression tests when appropriate and commit. If a change
legitimately needs another exact Rust file (including a test or a new module),
claim it **before** changing it:

```bash
"$tool" extend "$state" agent-1 src/shared_helper.rs tests/regression.rs
"$tool" checkpoint "$state" agent-1  # optional: save committed work remotely
"$tool" publish "$state" agent-1 'cargo +stable test --locked --test regression'
```

Publication requires a clean committed worktree, with an actual difference
confined to the claimed paths. It merges the current target into that
worker's branch, verifies the resulting diff, and scans the exact candidate.
It requires a strict reduction in owned findings, rejects new per-file lint
categories/counts inside the claim and new diagnostic buckets outside it,
runs formatting, stable all-target Clippy, source policy, the campaign
regression command and the optional additional focused command. Compiler and
safety failures are fatal in the inventory itself. The gate also saves the
exact patch for review of newly justified expectations. Do not manufacture
progress with suppressions or change numeric tolerances. Use the project's
normal, narrow reasoned expectations only where justified.

The worker pushes the validated commit to the target using an ordinary
fast-forward push. If another worker won the race, Git rejects the push; the
worker incorporates the new tip and repeats validation. After four attempts
the claim remains active for a later retry instead of discarding source.
There is no central integrator or privileged merge API. Successful
publication releases the claim, removes the isolated worktree/worker build
directory, and deletes only the optional remote checkpoint ref whose verified
commit is now contained in the target. It preserves the target's whole history.
Repeat claim/edit/publish until no worthwhile files remain.

## Progress and recovery

```bash
"$tool" status "$state"
"$tool" release "$state" agent-1
"$tool" defer "$state" agent-2 'Needs coordinated change to another API'
"$tool" retry "$state" src/blocked.rs
```

Status refreshes from the remote and shows all diagnostic file counts,
active claims and deferred files. Claims are never silently stolen or timed
out: release/defer require an unchanged or already published clean checkout.
Deferral is keyed to file content, so editing that file makes it eligible
again; `retry` clears the deferral explicitly. Deferral does not make the
strict gate pass. For interrupted work, resume the existing claim or publish
an intermediate checkpoint before making any intentional abandonment decision.
Never run ordinary editing on the target checkout while the campaign owns
the branch. An external merge is allowed only when coordinated with current
claims; a source-level merge conflict remains in the worker checkout for
explicit resolution.

Logs, inventories, review patches and durable claim information live under
the external state directory. No policy or automation file is added to the
target project. Nontracked or unlocated diagnostics are visible in the
inventory but cannot be automatically claimed as ordinary Rust files. Resolve
those explicitly. Keep the primary checkout untouched while workers publish;
when idle, fetch and fast-forward it to the target.

## Finish

When claims are released and the target is ready:

```bash
"$tool" finish "$state" 'cargo +stable test --workspace --locked'
```

The final command runs the real, normal strict CI gate and the complete
project regression command on a clean detached checkout of the current
remote tip. It rejects outstanding claims, failures or a changed target
revision. Include project goldens, reference checks and other required tests
in the final command. Successful completion unregisters the campaign while
retaining its evidence; normal PR review/CI then proceeds as usual.

Use `bash checks/test_lint_campaign.sh` with managed sccache to exercise the
real two-worker Git/Cargo fixture, conflict-free stale-base merge, claim
overlap, no-progress and formatting rejection, failed focused checks,
deferral, final strict rejection and final successful completion.
