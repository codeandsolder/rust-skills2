# Strict reusable Rust CI gate

The rust-skills2 CI gate turns the mechanically enforceable high-signal rules
into one centrally maintained GitHub Actions check.

## One-line job import

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
```

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
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
    with:
      allow-test-panics: true
```

With the default `--all-targets` selector, `allow-test-panics` first runs
the full policy against library, binary, and example targets. It then runs the
all-targets pass with test/benchmark-only non-correctness policy relaxed:
the `style`, `complexity`, `pedantic`, and `nursery` groups plus
`unwrap_used`, `expect_used`, `panic`, `panic_in_result_fn`,
`missing_panics_doc`, and `assertions_on_constants`. The `correctness`,
`suspicious`, and `perf` groups remain fatal even in tests; the gate reasserts
those groups and hard safety/debug lints after the test-only allows because
command-line lint ordering is significant. Production
targets therefore still pass the uncompromised policy. Source-level suppression
rules remain unchanged.

For a Rust workspace below the repository root:

```yaml
jobs:
  rust-skills2:
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
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
    uses: codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@main
    with:
      cargo-args: "--locked --workspace --all-targets --all-features"
```

## Policy

The gate always runs the latest nightly rustfmt and Clippy so formatting drift and new diagnostics are surfaced
early. It deliberately supplies its own strict `clippy.toml`, so a repository
cannot weaken the shared gate with repository-local settings. Test panic
ergonomics are available only through the explicit reusable-workflow opt-in
described above; const evaluation and production targets remain strict.

The policy pass clears both `RUSTC_WRAPPER` and `RUSTC_WORKSPACE_WRAPPER`. The rust-skills2 example/fixture verifier does the same for all Cargo invocations. Clippy reads its configuration during
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

## Scope

This gate is intentionally only the reusable language-policy layer. Projects
still own target matrices, service dependencies, integration/E2E tests, Miri
selection, wasm/embedded builds, generated-source checks, and other
domain-specific CI.
