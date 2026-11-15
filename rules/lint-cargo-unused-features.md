# lint-cargo-unused-features

> Audit unused Cargo feature flags; distinguish Cargo 1.100’s stable lint infrastructure from the still-experimental feature lint

**Rule**: `lint-cargo-unused-features`

**Status**: 🚧 The `unused_features` lint itself is not known to be stable in Cargo 1.100. The `[lints.cargo]` infrastructure **is stable** since Cargo 1.100 and includes the separate `cargo::unused_dependencies` lint.
Tracking issue: [rust-lang/cargo#12158](https://github.com/rust-lang/cargo/issues/12158).

## Why It Matters

Feature flags declared in `Cargo.toml` `[features]` that are never referenced in
code, `cfg()` expressions, or dependency gates accumulate over time. They make
the API surface misleading and increase maintenance burden. A future Cargo lint
will detect these automatically; until then, review and prune features manually.

## Bad

```toml
[features]
default = ["std"]
std = []              # Used — OK
experimental = []      # BAD: never referenced in cfg or dependencies
legacy_v2 = []         # BAD: was used by v0.2 migration, now dead
```

## Good

```toml
[features]
default = ["std"]
std = []

# Only features that are actually used in cfg(feature = "...") or
# as optional dependency gates
```

## Configuration (Nightly Only)

Only use the experimental unused-feature lint on a nightly Cargo version where it actually exists. Do **not** confuse this with the stabilized `cargo::unused_dependencies` lint:

```toml
# Cargo.toml (experimental lint; not stable on 1.100)
[lints.cargo]
unused_features = "deny"
```

Or at the workspace level:

```toml
# Root Cargo.toml (experimental lint; not stable on 1.100)
[workspace.lints.cargo]
unused_features = "deny"
```

> **Note**: The exact lint name and stabilization version are pending. Track
> [cargo#12158](https://github.com/rust-lang/cargo/issues/12158) for progress.

## What It Would Catch

### Unused Feature Flags

```toml
[features]
my_feature = []  # Not used in any cfg(feature = "my_feature")

[target.'cfg(not(target_os = "windows"))'.dependencies]
# No reference to my_feature anywhere
```

### Features That Only Exist for Documentation

```toml
[features]
# Used to be opt-in, now is always enabled
unstable_api = []  # No references in code → flagged
```

## Manual Cleanup Workflow

While the lint is unstable, prune unused features manually:

```bash
# 1. List declared features
rg 'cfg(feature\s*=' src/ | sort -u

# 2. Cross-reference with Cargo.toml [features]
#    Features not appearing in any cfg!(feature = "...") are candidates

# 3. Remove unused features from Cargo.toml
# 4. Verify nothing broke
cargo check --all-features
cargo test --all-features
```

## See Also

- [Cargo issue #12158 — Cargo lints](https://github.com/rust-lang/cargo/issues/12158)
- [Cargo unstable features — lints.cargo](https://doc.rust-lang.org/nightly/cargo/reference/unstable.html#lintscargo)
- [Cargo reference — Features](https://doc.rust-lang.org/cargo/reference/features.html)
- [lint-cargo-metadata](./lint-cargo-metadata.md) — Cargo metadata lints
- [lint-cargo-unused-dependencies](./lint-cargo-unused-dependencies.md) — the stable Cargo 1.100 dependency lint
