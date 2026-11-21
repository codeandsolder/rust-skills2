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

For a long-lived campaign, provision a dedicated Rustup home with its
`toolchains/nightly-<host>` and `toolchains/stable-<host>` aliases pointing
to installed dated nightly and numbered stable toolchains, respectively.
Do not point these aliases at the host's moving toolchains. Keep the
installation available until the campaign is finished. Initialize with
`LINT_CAMPAIGN_RUSTUP_HOME=/absolute/path/to/pinned-rustup`; the campaign
persists that home and exports it for workers, validation and focused tests.

To adopt the same isolation in an existing campaign, pause new commands
with the state's `migrating` marker, stop the sole validator, and wait
for any in-flight worker commands to exit. Run
`lint_campaign.sh upgrade STATE /absolute/path/to/pinned-rustup` from the
updated clean policy checkout, then restart the existing validator service.
Upgrade checks both pinned compiler versions and preserves the lint policy,
claims, and inventories. If a validator was interrupted while using a
different compiler, discard any inventory computed with that compiler
before restarting; the durable running queue job is retried automatically.

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

Publication is now **submission**, not synchronous validation. It checks
the clean commit and file scope, creates a durable queue checkpoint ref,
transfers the file reservation to the queue, and removes the editor
worktree. The same worker ID is immediately free to claim another set.
No compiler runs in this path. Do not wait for the submitted job.

Start exactly one long-lived validator on the shared host. Queue serialization
does not serialize compilation: the campaign defaults to 32 Cargo jobs
and clamps inherited positive job counts below 16 to 16. Do not add lower
explicit job-count overrides to focused commands. The existing managed
sccache and distributed worker configuration remain in use.

```bash
"$tool" serve "$state"
```

Run it as a managed user service for unattended campaigns, with the managed
sccache wrapper, Cargo configuration and any project reference tools in
its environment. For finite manual processing, use
`"$tool" drain "$state"`; both commands share the same exclusive
validator lock.

The validator processes FIFO jobs in a dedicated reusable detached
worktree. It incorporates the latest target, reuses the accepted tip's
cached lint inventory, scans the exact candidate once, checks scope and
lint delta, and runs formatting, stable all-target Clippy, source policy,
shared and focused regressions. It alone pushes accepted candidates
directly to the target. There is no designated integration agent, no
competing validation loop, and no per-worker revalidation on each merge.
A non-campaign external target update may cause a non-fast-forward push
failure; the candidate is retained for recovery rather than force-pushed.

Queue reservations remain disjoint from all editor reservations, including
failed submissions. Each job has an immutable source checkpoint and a
persistent status: staging, pending, running, published, failed, or
recovered. Failed validation never stops subsequent jobs. Check results
between batches, and recover a failed job into a free worker ID when ready:

```bash
"$tool" results "$state" agent-1
"$tool" recover "$state" 000000001 agent-1
```

Inspect the queue job log and referenced gate log, fix its retained source,
and submit again. A successful merge releases that job's reservations and
cleans up its checkpoint refs when they are ancestors of the accepted tip.
If the editor already has another claim, finish it first or recover using a
different free worker ID.

## Progress and recovery

```bash
"$tool" status "$state"
"$tool" release "$state" agent-1
"$tool" defer "$state" agent-2 'Needs coordinated change to another API'
"$tool" retry "$state" src/blocked.rs
```

Status uses the latest cached accepted inventory and shows file counts,
active claims, queued submissions and deferred files. Only the serial
validator refreshes a missing target inventory. Claims are never silently stolen or timed
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

When the queue is empty, the final command excludes the validator and runs the real, normal strict CI gate and the complete
project regression command on a clean detached checkout of the current
remote tip. It rejects outstanding claims, failures or a changed target
revision. Include project goldens, reference checks and other required tests
in the final command. Successful completion unregisters the campaign while
retaining its evidence; normal PR review/CI then proceeds as usual. To abandon
an unfinished campaign, release all clean claims and use `stop STATE`; it
unregisters and archives evidence without representing the strict gate as passed.

Use `bash checks/test_lint_campaign.sh` with managed sccache to exercise the
real Git/Cargo fixture, exclusive serial validation, immediate reassignment
while an earlier job is running, queued-file reservations, stale-base merge,
no-progress and failed focused-check recovery, deferral, final strict
rejection and final successful completion.

## Issue queues after strict cleanup

The same validator can coordinate larger, dependency-ordered refactors
without requiring a lint count reduction. Initialize a fresh campaign only
after the lint campaign has finished and the target inventory is empty:

```bash
"$tool" init-issues "$state" "$target" "$worktrees" /absolute/issue-plan.json \
  'cargo +stable test --workspace --locked'
"$tool" serve "$state"
```

The manifest is an ordered JSON array (dependencies must precede dependants).
Each task has a unique string issue number, title, dependencies and starting
scope. Exact repository-relative paths may include new files; directory
prefixes ending in / expand to tracked files at claim time.

```json
[
  {"id":"10","title":"Introduce checked handles","depends":[],"paths":["src/index.rs"]},
  {"id":"11","title":"Use checked handles in solver","depends":["10"],"paths":["src/solver/"]}
]
```

Workers use `issues STATE` to inspect readiness and `claim-issue STATE WORKER
[ISSUE_ID]` to take the first ready task or an explicitly requested ready task.
Only successfully published prerequisite tasks unblock dependants. Active,
queued and failed tasks reserve their exact file scopes until publication,
recovery or release. Extend a claim before editing additional files. The
same publish/results/recover protocol applies; issue submissions require a
focused regression command. Give the issue's acceptance evidence in the
commits and link the accepted revision on GitHub after publication. A
published receipt means the declared work passed the gates, not that the
tool independently judged the entire issue's design complete. Do not close
a GitHub issue merely because a partial implementation passed.

Every accepted issue revision must keep the strict inventory empty; the
shared and focused gates still run on the merged candidate. Finish refuses
while any task remains unpublished. Use a new manifest for the next wave,
rather than editing a live plan or manually overriding dependencies.
