# lint-cargo-unused-features

> Detect unused feature flags declared in Cargo.toml (`[lints.cargo]`, nightly-only)

**Rule**: `lint-cargo-unused-features`

**Status**: 🚧 Unstable — this lint has not yet been stabilized. The Cargo linting
infrastructure (`-Zcargo-lints` / `[lints.cargo]`) is still nightly-only.
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

When the Cargo linting infrastructure is available, configure under `[lints.cargo]`:

```toml
# Cargo.toml (requires nightly + -Zcargo-lints)
[lints.cargo]
unused_features = "deny"
```

Or at the workspace level:

```toml
# Root Cargo.toml (requires nightly + -Zcargo-lints)
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
grep -r 'cfg(feature\s*=' src/ | sort -u

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
