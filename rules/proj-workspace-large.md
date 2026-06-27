# proj-workspace-large

> Use workspaces for large projects

## Why It Matters

Cargo workspaces manage multiple related crates under one repository. They share a single `Cargo.lock`, build cache, and can be versioned together. For large projects, workspaces improve build times, enforce modularity, and simplify dependency management.

## Bad

```
# Separate repositories for each crate
my-app-core/
my-app-cli/
my-app-server/
my-app-common/

# Each has its own Cargo.lock
# Dependencies may drift
# Cross-crate development is painful
```

## Good

```
my-app/
├── Cargo.toml          # Workspace root
├── Cargo.lock          # Shared lock file
├── crates/
│   ├── core/
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── cli/
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── server/
│   │   ├── Cargo.toml
│   │   └── src/
│   └── common/
│       ├── Cargo.toml
│       └── src/
└── README.md
```

## Workspace Root: Modern Template (Rust 1.90+)

```toml
# Root Cargo.toml — virtual workspace (no [package])
[workspace]
resolver = "3"
members = ["crates/*"]

[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"
rust-version = "1.85"
repository = "https://github.com/user/repo"
authors = ["My Team <team@example.com>"]

# Shared dependencies — all crates use same versions
[workspace.dependencies]
tokio = { version = "1.32", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
tracing = "0.1"
anyhow = "1.0"

# Shared lints
[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
all = "warn"
unwrap_used = "deny"
```

## Member Crate Cargo.toml

```toml
# crates/core/Cargo.toml
[package]
name = "my-app-core"
version.workspace = true
edition.workspace = true
license.workspace = true
rust-version.workspace = true
repository.workspace = true

[dependencies]
# Inherit from workspace
tokio.workspace = true
serde.workspace = true

# Crate-specific dependencies
uuid = "1.0"

# Internal dependency via workspace deps
my-app-common.workspace = true

[lints]
workspace = true  # Inherit workspace lints
```

## `crates/*` Layout: Flat over Nested

Prefer flat `crates/*` over deeply nested directories:

```toml
# ❌ Nested (harder to navigate, glob patterns break)
members = [
    "backend/core",
    "backend/cli",
    "backend/server",
    "frontend/app",
    "frontend/shared",
]

# ✅ Flat (clear structure, simple glob)
members = ["crates/*"]

# Or explicit list
members = [
    "crates/core",
    "crates/cli",
    "crates/server",
    "crates/app",
]
```

```
# Flat layout
my-app/
├── Cargo.toml          # Virtual workspace root
├── Cargo.lock
├── crates/
│   ├── core/           # my-app-core
│   ├── cli/            # my-app-cli
│   ├── server/         # my-app-server
│   └── common/         # my-app-common
└── README.md
```

## Pattern: Virtual Workspace

Root `Cargo.toml` has only `[workspace]`, no `[package]`:

```toml
[workspace]
members = ["crates/*"]
resolver = "3"

[workspace.package]
# ...metadata inherited by all members

[workspace.dependencies]
# ...shared dependencies

[workspace.lints]
# ...shared lints
```

Virtual workspaces prevent accidental publication of a root crate and keep the root focused on orchestration.

## Pattern: Crate Interdependencies with Version Fallback

```toml
# Root Cargo.toml
[workspace.dependencies]
my-app-core = { path = "crates/core", version = "0.1" }  # version = fallback for publish
my-app-common = { path = "crates/common", version = "0.1" }

# crates/server/Cargo.toml
[dependencies]
my-app-core.workspace = true
my-app-common.workspace = true
```

Using `path + version` in workspace deps means published crates resolve via version, local builds use path.

## When to Use Workspaces

| Scenario | Recommendation |
|----------|----------------|
| Single binary/library | No workspace needed |
| Library + CLI | Maybe, depends on size |
| Multiple related crates | Yes |
| Shared internal libraries | Yes |
| Microservices mono-repo | Yes |
| Plugin architecture | Yes |

## Benefits

| Aspect | Single Crate | Workspace |
|--------|--------------|-----------|
| Build cache | Crate only | Shared across all |
| Dependency versions | Per-crate | Synchronized |
| Compile times | Full rebuild | Incremental |
| Modularity | Files/modules | Crate boundaries |
| Publishing | Single crate | Independent or `--workspace` |

## Commands

```bash
# Build all crates
cargo build --workspace

# Build specific crate
cargo build -p my-app-core

# Test all crates
cargo test --workspace

# Run specific binary
cargo run -p my-app-cli --bin server

# Check all
cargo check --workspace

# Publish all (Rust 1.90+)
cargo publish --workspace --dry-run
```

## Known Pitfalls

- **Feature unification** — workspace members share feature activation. `crate-a` enabling `tokio/full` activates it for all members. See [proj-workspace-deps](./proj-workspace-deps.md) for mitigations.
- **`default-features = false`** — does not compose with `{dep}.workspace = true` (cargo#12162). Define minimal-feature variants in workspace deps instead.
- **`resolver = "3"`** — required for Edition 2024. Workspaces created with older editions should update explicitly.

## See Also

- [proj-workspace-deps](./proj-workspace-deps.md) - Workspace dependencies
- [proj-bin-dir](./proj-bin-dir.md) - Multiple binaries
- [proj-lib-main-split](./proj-lib-main-split.md) - Lib/main separation
