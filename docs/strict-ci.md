# Strict reusable CI gate

The rust-skills2 CI gate turns the mechanically enforceable high-signal Rust
and Python rules into one centrally maintained GitHub Actions check.

## One-line job import

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
```

Pin the reusable workflow to an immutable full commit SHA and keep the tracked branch in an end-of-line comment (`@<full-commit-sha> # main`). Renovate understands that form and can advance the digest while preserving immutable execution; a bare SHA has no branch identity for Renovate to follow.

The default gate runs:

```text
cargo +nightly fmt --all --check
cargo +nightly clippy --locked --workspace --all-targets -- <strict policy>
```

Projects that deliberately use panic-style test assertions can opt in to a
split pass:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
    with:
      allow-test-panics: true
```

With the default `--all-targets` selector, `allow-test-panics` first runs
the full policy against the selected workspace/packages' actual default production
targets (library and/or binaries), then against examples. This works for
library-only, binary-only, and mixed crates without inventing target kinds that
do not exist. It then runs the all-targets pass with test/benchmark-only
non-correctness policy relaxed:
the `style`, `complexity`, `pedantic`, and `nursery` groups plus
`unwrap_used`, `expect_used`, `panic`, `panic_in_result_fn`,
`missing_panics_doc`, `assertions_on_constants`, test-only unsafe/safety-doc
annotation lints, and `unfulfilled_lint_expectations` (production expectations
can legitimately be inactive in a test compilation). The `correctness`,
`suspicious`, and `perf` groups remain fatal even in tests, as do `todo`,
`unimplemented`, `dbg_macro`, and `await_holding_lock`; the gate reasserts them
after the test-only allows because command-line lint ordering is significant.
Production targets therefore still pass the uncompromised policy. Source-level
suppression rules remain unchanged.

For workspaces, that policy is automatically inherited by every selected member.
New members need no lint stanza of their own: the gate discovers them with
`cargo metadata` and applies the workspace default. A legacy or upstream-heavy
member can opt into relaxed test/bench panic ergonomics without weakening
production code or its siblings:

```toml
[package.metadata.rust-skills2]
allow-test-panics = true
allow-test-panics-reason = "Inherited upstream tests; production remains strict"
```

A workspace-wide repository default can also live in the virtual/root manifest:

```toml
[workspace.metadata.rust-skills2]
allow-test-panics = true
allow-test-panics-reason = "Large inherited test suite; migrate opportunistically"
```

Package metadata wins over the workspace default, so a member can strengthen a
relaxed workspace back to strict with `allow-test-panics = false`. The reusable
workflow input remains the fallback default for repositories that do not declare
metadata. Any metadata change from strict to relaxed must include a non-empty
reason; strengthening overrides need no reason.

When a selected workspace mixes strict and relaxed members, the gate runs one
fully strict production pass and a strict examples pass for the selected set,
then groups test/bench Clippy runs by effective policy. The relaxed group allows
only the existing test ergonomics set; `correctness`, `suspicious`, `perf`,
`todo`, `unimplemented`, `dbg_macro`, and `await_holding_lock` remain fatal.

For a Rust workspace below the repository root:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
    with:
      working-directory: rust
```

Projects with unusual feature topology can change the Cargo-side selectors
without changing the lint policy. `cargo-args` is intentionally fail-closed:
it accepts workspace/package, feature, compilation target, target-kind, and
lock/offline selectors only. Arbitrary Cargo options are rejected, including
policy overrides (`--config`, `-Z`), rustc argument injection (a second
`--`), manifest redirection, mutating `--fix`, and early-exit options such as
`--help`, `--version`, or `--explain`:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
    with:
      cargo-args: "--locked --workspace --all-targets --all-features"
```

## Policy

The gate always runs the latest nightly rustfmt and Clippy so formatting drift and new diagnostics are surfaced
early. It deliberately supplies its own strict `clippy.toml`, so a repository
cannot weaken the shared gate with repository-local settings. Test panic
ergonomics are available only through the explicit reusable-workflow opt-in
described above; const evaluation and production targets remain strict.

The policy pass clears both `RUSTC_WRAPPER` and `RUSTC_WORKSPACE_WRAPPER` by default. The rust-skills2 example/fixture verifier does the same for all Cargo invocations. Clippy reads its configuration during compiler execution, so distributing clippy-driver to a worker that cannot see the action checkout can make the policy fail or diverge.

Trusted self-hosted runners may preserve a deterministic local compiler wrapper explicitly. `preserve-rustc-wrapper: true` opts in; `rustc-wrapper` may provide the wrapper path, and `sccache-server-port` may select an already-running sccache daemon. A local-only sccache daemon is suitable because it preserves compile caching while keeping clippy-driver in the runner's filesystem namespace. These wrapper inputs are rejected unless preservation is explicitly enabled.

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
    with:
      runner: '["self-hosted","Linux","X64","local-ci"]'
      preserve-rustc-wrapper: true
      rustc-wrapper: /usr/local/libexec/sccache-client
      sccache-server-port: "4228"
```

All compiler and Clippy lints are passed at `deny`, not `forbid`.
External derive/proc macros legitimately inject internal lint allowances;
forbidding either a group or a concrete lint can make rustc reject generated
code. Leptos/TypedBuilder, for example, emits an internal
`allow(clippy::panic)`.

Handwritten source still cannot waive the non-negotiable rules. The source
policy checker rejects `#[allow]` entirely and rejects `#[expect]` for:

- `unwrap_used`, `expect_used`, `panic`, `todo`, `unimplemented`,
  and `dbg_macro`;
- undocumented unsafe blocks and missing unsafe API documentation;
- blocking lock guards held across await;
- rustc `unexpected_cfgs`, `unsafe_op_in_unsafe_fn`, and stale lint
  expectations;
- every lint that the current nightly places in Clippy's `correctness`,
  `suspicious`, or `perf` groups, except the deliberately heuristic
  `large_enum_variant` lint when it is a single reasoned expectation.

This keeps policy strict at handwritten source boundaries while remaining
composable with proc-macro-generated implementation details.

Style, complexity, pedantic, and nursery are denied rather than forbidden.
They still fail CI. A narrow `#[expect(lint, reason = "...")]` is available
only for a genuine nightly false positive, generated-code issue, or similarly
unavoidable case.

Handwritten source and compiler configuration are checked before Clippy runs:

- any source-level `#[allow(...)]` or `#[warn(...)]` (including one nested in
  `cfg_attr`) is rejected, because either can lower a command-line `deny`;
- an expectation must name exactly one specific lint and include
  `reason = "..."`; it may not name a lint group;
- expectations for lints that the current nightly places in Clippy's
  `correctness`, `suspicious`, or `perf` groups are rejected, except
  `clippy::large_enum_variant`, whose own project rule requires a measured
  layout/allocation tradeoff rather than mechanical boxing;
- expectations of the explicit non-negotiable error/safety lints and the
  allow-policy lints are rejected;
- effective Cargo rustflags plus every environment variable containing
  `RUSTFLAGS` are rejected if they contain `--cap-lints` or
  `--force-warn`, both of which can turn a command-line deny into a
  non-failing warning.

The checker obtains group membership from `clippy-driver +nightly -W help` at
runtime instead of maintaining a stale copied list. This closes the suppression
gap left by keeping whole groups at `deny` for proc-macro compatibility.

Checked-in generated Rust is source-scanned by default. When a package must keep
generator-owned Rust in the repository (for example bindgen output), declare each
generated boundary as an exact file path in package metadata:

```toml
[package.metadata.rust-skills2]
generated-lint-boundaries = ["src/ffi/generated.rs"]
```

Only the listed `.rs` files are exempt from the handwritten-source suppression
checker; they are still compiled by the full strict Clippy command and therefore
must carry whatever generator-owned lint attributes are required. Declarations
must be relative files inside the package root, must exist, cannot name a
directory or escape with `..`, and cannot be a Cargo target entrypoint such as
`src/lib.rs` or `src/main.rs`. The file must also either visibly identify itself
as generated near the top (for example `@generated`, `automatically generated`,
`auto-generated`, or a conventional `generated by ... do not edit` marker), or
be a pure lint-scope/include wrapper whose checked-in literal `include!` targets
carry such generated markers. Include wrappers may contain attributes and
`include!` calls only; adding handwritten Rust items makes the boundary invalid.
Prefer regenerating or isolating generated code over adding a boundary, and
never use this for ordinary handwritten modules.

## Why `.expect()` is forbidden

An application can normally propagate a `Result`, return an explicit error or
exit status from its boundary, or use `let ... else` / pattern matching for an
`Option`. A library should return the error to its caller. An internal
invariant can likewise be represented in the type/state machine instead of
turning routine extraction into a latent process abort.

If a project truly requires deliberate abort semantics, that should be encoded
as an explicit project-level design decision rather than hidden behind
`.expect()`.

## Mandatory Python policy

The reusable workflow also checks every tracked `*.py`, `*.pyi`, and `*.pyw` file in the
repository checkout. This is mandatory when Python exists; repositories without
tracked Python are a no-op. The Python pass is repository-wide even when the Rust
workspace lives below the repository root.

Ruff runs in preview mode from `select = ALL`, with only rule families removed
that are unsuitable as a universal gate: documentation/process policy,
formatter-conflicting rules, high-noise security heuristics, broad complexity or
refactor quotas, and strongly project-specific style rules. Repository
per-file-ignore configuration is cleared and explicit files bypass exclude
configuration. Narrow, code-specific `# noqa: RULE` exceptions remain possible;
blanket suppressions are rejected by the enabled Ruff policy.

The same files are checked by `ty`. The central configuration enables the
soundness-oriented rules beyond ty's defaults (`missing-type-argument`, dynamic
decorator return checking, unsound assignment/return/yield checking, strict
generic narrowing and equality semantics, and blanket-ignore rejection) while
leaving ty's explicitly high-false-positive experimental families disabled.
Specific typed suppression comments remain available for genuine tool/modeling
limitations. `ty` warnings are promoted to gate failures.

For dependency resolution, each tracked Python file is assigned to its nearest
ancestor `pyproject.toml`. Every distinct Python project is synced with `uv
sync --locked --all-groups --all-extras --no-install-project` into a temporary
environment, then `ty` checks that file group against the matching environment.
Nested Python projects therefore work independently, the source project itself
does not need to be built merely to type-check it, and no `.venv` is left in the
checkout. A Python project must keep its uv lockfile current; the gate never
rewrites dependency state. Standalone Python outside any `pyproject.toml` is
still checked and can resolve first-party/stdlib imports, but undeclared external
dependencies fail as unresolved imports rather than depending on runner state.

Python is CI-only by default. Repositories with a deliberate non-CI Python surface must opt out of the separate location gate explicitly:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@<full-commit-sha> # main
    with:
      ban-python-outside-ci: false
```

The built-in CI-only prefixes are `.github/`, `.gitlab/`, `.circleci/`,
`.buildkite/`, `.ci/`, `ci/`, `scripts/ci/`, and `tools/ci/`. Unusual layouts
can add narrow repository-relative directory prefixes without weakening Ruff or
ty:

```yaml
      python-ci-paths: |
        maintenance/ci
        packaging/ci
```

`ban-python-outside-ci` defaults to `true`; Ruff and ty are mandatory whenever tracked Python exists, including repositories that explicitly opt out of the location restriction.

## Scope

This gate is intentionally only the reusable language-policy layer. Projects
still own target matrices, service dependencies, integration/E2E tests, Miri
selection, wasm/embedded builds, generated-source checks, and other
domain-specific CI.
