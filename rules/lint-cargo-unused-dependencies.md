# lint-cargo-unused-dependencies

> Use Cargo 1.100's `cargo::unused_dependencies` lint for manifest hygiene; check all relevant targets before trusting an absence of warnings

**Rule**: `lint-cargo-unused-dependencies`

## Why It Matters

Cargo 1.100 stabilizes Cargo-native manifest lints under `[lints.cargo]` and starts warning about unused ordinary dependencies with `cargo::unused_dependencies`. This is distinct from rustc's `unused_crate_dependencies`, which may produce false positives when Cargo builds only one target from a package with shared dependencies.

## Good: Explicit Strict Manifest Policy

```toml
# Cargo.toml, Rust/Cargo 1.100+
[lints.cargo]
unused_dependencies = "deny"
```

For a workspace that inherits lints:

```toml
[workspace.lints.cargo]
unused_dependencies = "deny"
```

Members must opt into inherited workspace lints with `[lints] workspace = true`, exactly as with other Cargo workspace lints.

## Coverage Limits

- Cargo only reports an ordinary dependency unused once **every target that might use it** has been built. `cargo check --bin one` cannot establish that `[dependencies]` entries are unused elsewhere.
- Unused `[dev-dependencies]` are not reported by this lint; there is no general "every dev target compiled" proof yet.
- Platform-specific, optional, build, proc-macro, and feature-gated dependencies need the matching target/feature analysis; don't delete them based on a single host's build.
- The lint is useful as a CI signal but does not replace `cargo tree -e features`, target coverage, or review of dependency purpose.

## See Also

- [lint-cargo-unused-features](./lint-cargo-unused-features.md) — manual feature audit; no recognized feature lint
- [proj-workspace-deps](./proj-workspace-deps.md) — workspace inheritance
- [Cargo 1.100 changelog](https://doc.rust-lang.org/cargo/CHANGELOG.html#cargo-1100-2026-11-12)
