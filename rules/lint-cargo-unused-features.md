# lint-cargo-unused-features

> Detect unused feature flags declared in Cargo.toml (Rust 1.88+)

**Rule**: `lint-cargo-unused-features`

## Why It Matters

The `cargo_unused_cargo_features` lint (stabilized in Rust 1.88) detects feature flags declared in `Cargo.toml` `[features]` that are never used anywhere in the crate. Unused features accumulate over time, making the API surface misleading and increasing maintenance burden. This lint keeps the feature set honest.

## Bad

```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2024"

[features]
default = ["std"]
std = []              # Used — OK
experimental = []      # BAD: never referenced in cfg or dependencies
legacy_v2 = []         # BAD: was used by v0.2 migration, now dead

[dependencies]
serde = { version = "1", optional = true }
```

## Good

```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2024"

[features]
default = ["std"]
std = []

# Only features that are actually used in cfg(feature = "...") or
# as optional dependency gates

[dependencies]
serde = { version = "1", optional = true }
```

## Configuration

```toml
# Cargo.toml
[lints.rust]
cargo_unused_cargo_features = "deny"
```

Or at the workspace level:

```toml
# Root Cargo.toml
[workspace.lints.rust]
cargo_unused_cargo_features = "deny"
```

## What It Catches

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

## Integration with Cargo Cache (1.88)

Since Rust 1.88, Cargo's feature resolution integrates with the global cache. The `cargo_unused_cargo_features` lint works with:

- `cargo tree -e features` — visualize feature usage
- `cargo metadata` — inspect declared vs used features
- `cargo update` — cache-aware feature resolution

## Cleanup Workflow

```bash
# 1. Enable the lint
cargo clippy  # Reports unused features

# 2. Remove unused features from Cargo.toml
# 3. Verify nothing broke
cargo check --all-features
cargo test --all-features
```

## See Also

- [Rust 1.88.0 release notes](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0/)
- [Cargo reference — Features](https://doc.rust-lang.org/cargo/reference/features.html)
- [lint-cargo-metadata](./lint-cargo-metadata.md) — Cargo metadata lints
