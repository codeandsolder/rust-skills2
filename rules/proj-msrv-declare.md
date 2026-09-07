# proj-msrv-declare

> Declare `rust-version` (MSRV) in Cargo.toml and test it in CI

## Why It Matters

`package.rust-version` tells Cargo and downstream users which Rust release line the package promises to support. Setting it produces a clear, actionable error when the installed toolchain is too old instead of a cryptic type or feature error deep inside your code.

For Rust 2024 workspaces, resolver 3 makes dependency resolution MSRV-aware: Cargo prefers dependency versions whose own `rust-version` does not exceed the workspace/package compatibility floor. This prevents an ordinary dependency update from silently selecting a release your stated MSRV cannot compile.

But **MSRV and the toolchain used for day-to-day development are different policies**. Keeping every developer and production build frozen on the oldest supported compiler means missing compiler fixes, diagnostics, optimizer improvements, and point-release miscompilation fixes. A common modern setup is:

- `rust-version = "1.94"` as the compatibility promise;
- an explicit CI lane on the latest 1.94 patch release (for example 1.94.1);
- `rust-toolchain.toml` pinned to the patched current stable compiler used for normal development and shipping (for example 1.98.1 while Rust 1.98 is current).

## Bad

```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2024"
# no rust-version — no explicit compatibility contract
```

Also avoid treating the MSRV itself as the only compiler the project is ever allowed to use:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.94.0" # BAD if 1.94 is only the compatibility floor and newer patched stable exists
```

That conflates “oldest supported” with “preferred compiler for all builds.”

## Good: Library or Application With an Older Compatibility Floor

```toml
# Cargo.toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2024"
rust-version = "1.94"

[workspace]
resolver = "3"
```

```toml
# rust-toolchain.toml — normal development/build toolchain
[toolchain]
channel = "1.98.1"
components = ["rustfmt", "clippy"]
```

CI should test the floor separately:

```yaml
jobs:
  msrv:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup toolchain install 1.94.1 --profile minimal
      - run: cargo +1.94.1 check --locked --workspace --all-targets

  current:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup toolchain install 1.98.1 --profile minimal --component clippy
      - run: cargo +1.98.1 clippy --locked --workspace --all-targets -- -D warnings
      - run: cargo +1.98.1 test --locked --workspace
```

Point releases normally do not raise the language/library MSRV: they are bug-fix releases in the same stable line. Testing the latest patch release for the declared minor line gets those fixes without changing the compatibility promise.

## Resolver 3: Virtual Workspaces Need It Explicitly

Edition 2024 packages use resolver 3 by default, but a **virtual workspace root has no package edition from which Cargo can infer a resolver**. Declare it explicitly:

```toml
[workspace]
resolver = "3"
members = ["crate-a", "crate-b"]

[workspace.package]
edition = "2024"
rust-version = "1.94"
```

Do not assume `[workspace.package].edition = "2024"` silently changes the virtual workspace resolver. Make the dependency-resolution policy visible.

Resolver 3 improves dependency selection, but it is not a replacement for actually compiling on the MSRV. Existing lockfiles, feature combinations, build dependencies, generated code, or project source can still violate the floor.

## Rust 1.94+: Distinguish Crate MSRV From Development-Manifest MSRV

Cargo 1.94 added TOML 1.1 parsing for manifests and Cargo configuration. Features such as multiline inline tables are convenient:

```toml
serde = {
    version = "1.0",
    features = ["derive"],
}
```

Using TOML 1.1-only syntax means an older Cargo cannot parse the repository's source `Cargo.toml`, even if the Rust source itself would compile on that older toolchain. Rust calls this a **development MSRV** distinction.

For published crates, Cargo rewrites the manifest during `cargo publish` to remain compatible with older manifest parsers, so it is possible for:

- the source repository to require Cargo/Rust 1.94+ to work on directly;
- the published crate to retain an older `package.rust-version` for downstream consumers.

Document that distinction if you rely on it. For applications, unpublished workspaces, git dependencies, or contributors who must build directly from source, the manifest parser floor is a real part of the effective toolchain requirement.

Third-party tooling that parses Cargo TOML may also lag TOML 1.1, so do not adopt newer syntax merely for aesthetics when compatibility with that tooling matters.

## Choosing and Maintaining MSRV

- Pick the oldest stable toolchain your users realistically need (distro packages, embedded targets, corporate freeze windows, downstream library policy).
- Do not go lower merely for prestige: a lower floor increases compatibility work and can constrain dependency versions.
- Keep normal development/production builds on a patched stable compiler unless reproducibility or certification requirements call for another explicit policy.
- When a Rust point release fixes a compiler miscompilation, prefer the patched point release rather than pinning the superseded `.0` indefinitely.
- Test important feature/target combinations on the MSRV, not just one trivial default build.
- Run the current stable compiler too; an MSRV-only CI matrix can miss new warnings, linker-policy changes, or forward-compatibility regressions.
- When you intentionally bump a library MSRV, document the change in the changelog/release notes and follow the project's compatibility/versioning policy.
- Tools such as `cargo-msrv` can help discover the apparent source floor, but the supported MSRV remains a project contract that CI should enforce.

## Lockfiles and MSRV

For applications and committed-lockfile workspaces, test with `--locked`. Resolver 3 only influences dependency selection when Cargo resolves; it does not magically rewrite an already-committed graph into an MSRV-compatible one.

For libraries, consider both the published resolver behavior and whatever lockfile policy you use for CI. A passing current-stable build does not prove that the declared floor can compile the dependency graph.

## See Also

- [proj-workspace-deps](proj-workspace-deps.md) - use workspace dependency inheritance
- [lint-cargo-metadata](lint-cargo-metadata.md) - warn on missing Cargo.toml metadata
- [doc-cargo-metadata](doc-cargo-metadata.md) - fill Cargo.toml metadata fields
- [lint-edition-2024](lint-edition-2024.md) - Edition 2024 migration/lint guidance