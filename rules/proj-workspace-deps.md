# proj-workspace-deps

> Use workspace dependency inheritance for consistent versions across crates

## Why It Matters

Multi-crate workspaces often have dependency version drift—different crates using different versions of the same dependency. Workspace dependency inheritance (Rust 1.64+) lets you declare dependencies once in the workspace `Cargo.toml` and inherit them in member crates, ensuring consistency.

## Bad

```toml
# crate-a/Cargo.toml
[dependencies]
serde = "1.0.150"
tokio = "1.25"

# crate-b/Cargo.toml  
[dependencies]
serde = "1.0.188"  # Different version!
tokio = "1.32"     # Different version!

# Version drift leads to:
# - Larger binaries (multiple versions)
# - Compilation time increase
# - Subtle behavior differences
```

## Good

```toml
# Root Cargo.toml
[workspace]
members = ["crate-a", "crate-b", "crate-c"]

[workspace.dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.32", features = ["full"] }
thiserror = "1.0"
anyhow = "1.0"
tracing = "0.1"

# crate-a/Cargo.toml
[dependencies]
serde.workspace = true
tokio.workspace = true

# crate-b/Cargo.toml
[dependencies]
serde.workspace = true
tokio.workspace = true
thiserror.workspace = true
```

## Override Features

```toml
# Root Cargo.toml
[workspace.dependencies]
tokio = { version = "1.32", features = ["rt-multi-thread"] }

# crate-a/Cargo.toml - add extra features
[dependencies]
tokio = { workspace = true, features = ["net", "io-util"] }
# Gets both workspace features AND local features

# crate-b/Cargo.toml - minimal features
[dependencies]
tokio = { workspace = true }  # Just workspace features
```

## Dev and Build Dependencies

```toml
# Root Cargo.toml
[workspace.dependencies]
criterion = "0.5"
proptest = "1.0"
trybuild = "1.0"
cc = "1.0"

# crate-a/Cargo.toml
[dev-dependencies]
criterion.workspace = true
proptest.workspace = true

[build-dependencies]
cc.workspace = true
```

## Internal Crate Dependencies

```toml
# Root Cargo.toml
[workspace.dependencies]
# Internal crates
my-core = { path = "crates/core" }
my-utils = { path = "crates/utils" }
my-derive = { path = "crates/derive" }

# External crates
serde = "1.0"

# crate-a/Cargo.toml
[dependencies]
my-core.workspace = true
my-utils.workspace = true
serde.workspace = true
```

## Optional Dependencies

```toml
# Root Cargo.toml
[workspace.dependencies]
serde = { version = "1.0", optional = true }  # Won't work!

# Optional must be set in member, not workspace
[workspace.dependencies]
serde = "1.0"

# crate-a/Cargo.toml
[dependencies]
serde = { workspace = true, optional = true }

[features]
serde = ["dep:serde"]
```

## `[workspace.package]` Inheritance (Rust 1.64+)

Declare shared package metadata once in the workspace root and inherit it in every member:

```toml
# Root Cargo.toml
[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"
rust-version = "1.85"
authors = ["My Team <team@example.com>"]
repository = "https://github.com/user/repo"
description = "My awesome project"

# crates/core/Cargo.toml
[package]
name = "my-core"
version.workspace = true
edition.workspace = true
license.workspace = true
rust-version.workspace = true
authors.workspace = true
repository.workspace = true
description.workspace = true
```

This prevents metadata drift — without inheritance, each crate may silently fall behind on `edition` or `rust-version`.

## `[workspace.lints]` Config (RFC 3389, stable 1.74+)

Centralize lint configuration in the workspace root and inherit in member crates:

```toml
# Root Cargo.toml
[workspace.lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"

[workspace.lints.clippy]
all = "warn"
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"

[workspace.lints.rustdoc]
missing_crate_level_docs = "warn"

# crates/core/Cargo.toml
[package]
name = "my-core"
version.workspace = true
edition.workspace = true

[lints]
workspace = true  # Inherit all workspace lints
```

> **Limitation**: It is a hard error to mix `lints.workspace = true` with per-crate overrides in the same `[lints]` table (cargo#13157). Use `#![allow(...)]` attributes in `lib.rs`/`main.rs` to override per crate.

## `resolver = "3"` (Edition 2024 Default)

Use `resolver = "3"` in the workspace. This is the default for Edition 2024 (Rust 1.85+) and respects `package.rust-version` for dependency selection.

```toml
[workspace]
members = ["crates/*"]
resolver = "3"  # Edition 2024 default; explicit for older editions
```

| Resolver | Edition | Behavior |
|----------|---------|----------|
| `"1"` | ≤ 2015 | Original resolver |
| `"2"` | 2021 | Conditional activation, target-specific deps |
| `"3"` | 2024 | `"2"` + respects `rust-version` in dependency resolution |

## Complete Workspace Example

```toml
# Root Cargo.toml
[workspace]
members = ["crates/*"]
resolver = "3"

[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"
rust-version = "1.85"
repository = "https://github.com/user/repo"

[workspace.dependencies]
# Internal
my-core = { path = "crates/core", version = "0.1" }

# Async
tokio = { version = "1.32", features = ["full"] }
futures = "0.3"

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# Error handling
thiserror = "1.0"
anyhow = "1.0"

# Logging
tracing = "0.1"
tracing-subscriber = "0.3"

# Testing
proptest = "1.0"
criterion = { version = "0.5", features = ["html_reports"] }

[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
all = "warn"
unwrap_used = "deny"

# crates/core/Cargo.toml
[package]
name = "my-core"
version.workspace = true
edition.workspace = true
license.workspace = true
rust-version.workspace = true

[dependencies]
serde.workspace = true
thiserror.workspace = true

[dev-dependencies]
proptest.workspace = true

[lints]
workspace = true
```

## Known Pitfalls

### Feature Unification (RFC 3692)

Workspace members share a single dependency graph. If `crate-a` enables `tokio/full` and `crate-b` enables `tokio/process`, all members see the union of features:

```toml
# crate-a enables "full"
# crate-b enables only "process"
# → All members compile with "full + process"
```

This can cause unexpected compile times or enable unwanted functionality. To opt out per-package (unstable):

```toml
# Requires cargo nightly
[workspace]
members = ["crates/*"]
resolver.feature-unification = "package"
```

### `default-features = false` with Workspace Dependencies (cargo#12162)

`default-features = false` does not compose with `{dep}.workspace = true` as expected. Workaround: specify the exact feature set in the workspace definition:

```toml
# ❌ default-features = false on workspace dep has no effect
[workspace.dependencies]
tokio = "1.32"

# crate-a/Cargo.toml
[dependencies]
tokio = { workspace = true, default-features = false, features = ["rt"] }

# ✅ Workaround: define the dep with minimal features in workspace
[workspace.dependencies]
tokio-minimal = { package = "tokio", version = "1.32", default-features = false }
tokio-full = { package = "tokio", version = "1.32", features = ["full"] }
```

## See Also

- [proj-lib-main-split](./proj-lib-main-split.md) - Workspace structure
- [api-serde-optional](./api-serde-optional.md) - Optional dependencies
- [lint-deny-correctness](./lint-deny-correctness.md) - Workspace lints
