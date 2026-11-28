# lint-cargo-unused-features

> Audit unused Cargo feature flags using their actual activation graph; Cargo 1.100 and the reviewed 1.102 nightly do not recognize an `unused_features` lint

## Why It Matters

Features create user-facing configuration contracts and affect the dependency graph.
An obsolete feature can mislead callers or keep unnecessary dependencies enabled.
An empty feature is not necessarily unused: another feature, downstream manifest,
conditional compilation expression, build script or supported compatibility contract
may consume it.

## Bad

```toml
[lints.cargo]
unused_features = "deny"
```

Cargo 1.100.0 and 1.102.0-nightly (2026-11-21 compiler commit) both report
`cargo::unknown_lints` for this name. Do not mistake the stable Cargo lint
infrastructure or the separate `cargo::unused_dependencies` lint for feature
usage analysis.

## Good

```toml
[features]
default = ["std"]
std = []
json = ["dep:serde_json"]
parse = ["json"]

[dependencies]
serde_json = { version = "1", optional = true }
```

Here `std` may be consumed by conditional compilation, `json` enables an optional
dependency, and `parse` forwards another feature. None can be judged unused from
an absence of an exact source-level `cfg(feature = "...")` expression alone.

## Audit the Actual Contract

- Inspect package and workspace manifests, feature forwarding, optional dependencies,
  feature selection in CI, target configuration, build scripts, examples and tests.
- Inspect conditional compilation and macros, including `cfg!` and `cfg_attr`.
- Use `cargo tree -e features` for the selected packages/configuration; repeat for
  relevant feature and target combinations.
- Remove obsolete features rather than preserving empty aliases when no downstream
  compatibility contract requires them. Validate affected callers, the default and
  no-default builds, and valid feature combinations.
- Do not assume `--all-features` is meaningful for mutually exclusive feature sets.

## See Also

- [proj-feature-additive](./proj-feature-additive.md) — feature contracts
- [proj-workspace-deps](./proj-workspace-deps.md) — feature unification
- [lint-cargo-unused-dependencies](./lint-cargo-unused-dependencies.md) — stable dependency lint
- [Cargo reference — Features](https://doc.rust-lang.org/cargo/reference/features.html)
- [Cargo lint infrastructure tracking](https://github.com/rust-lang/cargo/issues/12158)
