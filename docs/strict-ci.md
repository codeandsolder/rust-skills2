# Strict reusable Rust CI gate

The rust-skills2 CI gate turns the mechanically enforceable high-signal rules
into one centrally maintained GitHub Actions check.

## One-line job import

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
```

The default command is equivalent to:

```text
cargo +nightly clippy --locked --workspace --all-targets -- <strict policy>
```

For a Rust workspace below the repository root:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
    with:
      working-directory: rust
```

Projects with unusual feature topology can change the Cargo-side arguments
without changing the lint policy:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
    with:
      cargo-args: "--locked --workspace --all-targets --all-features"
```

## Policy

The gate always runs the latest nightly Clippy so new diagnostics are surfaced
early. It deliberately supplies its own strict `clippy.toml`, so a repository
cannot weaken the shared gate with settings such as allowing `.unwrap()` or
`.expect()` in tests or const evaluation.

The policy pass clears both `RUSTC_WRAPPER` and `RUSTC_WORKSPACE_WRAPPER`. Clippy reads its configuration during
compiler execution, so distributing clippy-driver to a worker that cannot see
the action checkout can make the policy fail or diverge. The reusable gate
therefore runs Clippy locally and relies on the normal target cache instead of
distributed compiler execution.

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
  `suspicious`, or `perf` groups.

This keeps policy strict at handwritten source boundaries while remaining
composable with proc-macro-generated implementation details.

Style, complexity, pedantic, and nursery are denied rather than forbidden.
They still fail CI. A narrow `#[expect(lint, reason = "...")]` is available
only for a genuine nightly false positive, generated-code issue, or similarly
unavoidable case.

Handwritten source is checked before Clippy runs:

- any source-level `#[allow(...)]` (including one nested in `cfg_attr`) is rejected;
- an expectation may name one specific lint, but may not name a lint group;
- expectations for lints that the current nightly places in Clippy's
  `correctness`, `suspicious`, or `perf` groups are rejected;
- expectations of `clippy::allow_attributes` and
  `clippy::allow_attributes_without_reason` are rejected.

The checker obtains group membership from `clippy-driver +nightly -W help` at
runtime instead of maintaining a stale copied list. This closes the suppression
gap left by keeping whole groups at `deny` for proc-macro compatibility.

Generated code is not source-scanned. It may lower lint levels internally
when the generator requires it; handwritten code still cannot lower the
non-negotiable categories above.

## Why `.expect()` is forbidden

An application can normally propagate a `Result`, return an explicit error or
exit status from its boundary, or use `let ... else` / pattern matching for an
`Option`. A library should return the error to its caller. An internal
invariant can likewise be represented in the type/state machine instead of
turning routine extraction into a latent process abort.

If a project truly requires deliberate abort semantics, that should be encoded
as an explicit project-level design decision rather than hidden behind
`.expect()`.

## Scope

This gate is intentionally only the reusable language-policy layer. Projects
still own target matrices, service dependencies, integration/E2E tests, Miri
selection, wasm/embedded builds, generated-source checks, and other
domain-specific CI.
