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

High-confidence rules are passed as `forbid`. A source-level `#[allow]` or
`#[expect]` therefore cannot suppress:

- Clippy correctness, suspicious, and performance groups;
- `unwrap_used`, `expect_used`, `panic`, `todo`, `unimplemented`,
  and `dbg_macro`;
- undocumented unsafe blocks and missing unsafe API documentation;
- blocking lock guards held across await;
- rustc `unexpected_cfgs`, `unsafe_op_in_unsafe_fn`, and stale lint
  expectations.

Style, complexity, pedantic, and nursery are denied rather than forbidden.
They still fail CI. A narrow `#[expect(lint, reason = "...")]` is available
only for a genuine nightly false positive, generated-code issue, or similarly
unavoidable case.

Outer `#[allow(...)]` attributes are forbidden by the gate. Use a narrow
`#[expect(..., reason = "...")]` for the suppressible groups instead.

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
