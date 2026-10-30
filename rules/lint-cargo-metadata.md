# lint-cargo-metadata

**Rule**: `lint-cargo-metadata`

> Enable clippy::cargo for published crates

## Why It Matters

The `clippy::cargo` lint group checks Cargo.toml for issues that affect publishing and dependency management. For crates intended for crates.io, these checks help ensure a professional, well-configured package.

## Edition 2024 & Minimum Rust Version

When targeting Edition 2024, update your `Cargo.toml` metadata:

```toml
[package]
edition = "2024"
rust-version = "1.85"  # Edition 2024 requires at least Rust 1.85
```

## Configuration

```toml
# Cargo.toml
[lints.clippy]
cargo = "warn"
```

Or in code:

```rust
#![warn(clippy::cargo)]
```

## What It Catches

### Missing Metadata

```toml
# WARN: missing package.description
# WARN: missing package.license or package.license-file
# WARN: missing package.repository
[package]
name = "my-crate"
version = "0.1.0"
```

### Dependency Issues

```toml
# WARN: feature used but not defined
# WARN: dependency version not specified
[dependencies]
serde = "*"  # Bad: any version
tokio = { git = "..." }  # WARN for published crates
```

### Feature Issues

```toml
# WARN: negative_feature_names
[features]
no-std = []  # Should be: std = [] (opt-out vs opt-in)

# WARN: redundant_feature_names
[features]
default = ["feature-a"]
feature-a = []  # Feature name matches crate name
```

## Notable Lints

| Lint | Issue |
|------|-------|
| `cargo_common_metadata` | Missing description/license/repository |
| `multiple_crate_versions` | Same crate at different versions |
| `negative_feature_names` | Features like `no-std` instead of `std` |
| `redundant_feature_names` | Feature same as crate name |
| `wildcard_dependencies` | Using `*` for version |

## Complete Cargo.toml

```toml
[package]
name = "my-crate"
version = "0.1.0"
edition = "2024"
rust-version = "1.85"

# Required for cargo lint satisfaction
description = "A short description of what this crate does"
license = "MIT OR Apache-2.0"
repository = "https://github.com/user/my-crate"

# Recommended
documentation = "https://docs.rs/my-crate"
readme = "README.md"
keywords = ["keyword1", "keyword2"]
categories = ["category-slug"]

# Workspace metadata (not lint-checked but recommended)
[workspace.metadata]
# Project-specific metadata

[dependencies]
# Specific versions, not wildcards
serde = "1.0"
tokio = { version = "1.0", features = ["full"] }

[features]
default = ["std"]
std = []  # Opt-out, not no-std opt-in

[lints.rust]
# Pass --check-cfg for all declared feature names (1.80+)
unexpected_cfgs = "warn"

[lints.clippy]
cargo = "warn"
```

## Multiple Crate Versions

```
# WARN: multiple versions of `syn` in dependency tree
# syn v1.0.109
# syn v2.0.48
```

Fix by updating dependencies or using `[patch]`:

```toml
[patch.crates-io]
old-dep = { git = "...", branch = "syn-2" }
```

## Internal / Unpublished Crates

Do not enable the whole `clippy::cargo` group merely to turn it back off with `allow`. For an internal crate, either omit that group when its publishing checks are irrelevant or enable the individual Cargo lints that still provide value.

When an enabled Cargo lint has a genuine source-local exception, use a narrow reasoned `#[expect]` where the diagnostic is owned. Do not set Cargo lint levels to `allow`.

## See Also

- [doc-cargo-metadata](./doc-cargo-metadata.md) - Cargo.toml metadata
- [proj-workspace-deps](./proj-workspace-deps.md) - Workspace dependencies
- [lint-deny-correctness](./lint-deny-correctness.md) - Correctness lints
