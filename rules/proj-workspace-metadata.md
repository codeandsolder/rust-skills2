# proj-workspace-metadata

> Use `[workspace.package]` for shared metadata inheritance

**Rule**: `proj-workspace-metadata`

## Why It Matters

Rust 1.64+ allows declaring package metadata (`version`, `edition`, `license`, `rust-version`, `authors`, `repository`, `description`) once in `[workspace.package]` and inheriting it in member crates with `field.workspace = true`. Without inheritance, each crate copies metadata independently — editions drift, `rust-version` lags behind, and license fields diverge.

Using `[workspace.package]` is mandatory best practice for any multi-crate workspace in 2026.

## Bad

```toml
# crates/core/Cargo.toml
[package]
name = "my-core"
version = "0.1.0"
edition = "2021"
license = "MIT"

# crates/cli/Cargo.toml
[package]
name = "my-cli"
version = "0.1.0"
edition = "2021"
license = "MIT"

# crates/server/Cargo.toml
[package]
name = "my-server"
version = "0.2.0"        # Drifted!
edition = "2021"
license = "MIT OR Apache-2.0"  # Different license!
```

Each crate must be manually kept in sync. A version bump touches every file; an edition upgrade requires changes across all members.

## Good

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
homepage = "https://my-project.dev"

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
homepage.workspace = true

# crates/cli/Cargo.toml — same inheritance
[package]
name = "my-cli"
version.workspace = true
edition.workspace = true
# ... etc
```

Changing `version` in one place propagates to every member. Edition upgrades, license changes, and author updates are a single line edit.

## Overriding Inherited Fields

Set `workspace = true` for the fields you want to inherit, then override specific fields locally:

```toml
# Root
[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"

# crates/server/Cargo.toml
[package]
name = "my-server"
version.workspace = true
edition.workspace = true
license = "MIT OR Apache-2.0"  # Local override
```

## Fields That Can Be Inherited

| Field | Inheritable | Notes |
|-------|-------------|-------|
| `version` | ✅ | Most common use |
| `edition` | ✅ | Critical for Edition 2024 migration |
| `license` | ✅ | Avoid SPDX drift |
| `rust-version` | ✅ | MSRV consistency |
| `authors` | ✅ | Typically same team |
| `repository` | ✅ | Same repo |
| `homepage` | ✅ | Same project site |
| `description` | ✅ | May differ per crate |
| `documentation` | ✅ | May differ per crate |
| `readme` | ✅ | May differ per crate |
| `keywords` | ✅ | May differ per crate |
| `categories` | ✅ | May differ per crate |
| `publish` | ✅ | Can override per crate |

## Anti-Pattern: Not Using Inheritance

```toml
# ❌ Explicit copy in every crate
# Every field is duplicated — edition bumps, version bumps,
# license changes all must be applied N times.
```

`[workspace.package]` is zero-cost and purely declarative. There is no reason to skip it in any workspace with two or more crates.

## See Also

- [proj-workspace-deps](./proj-workspace-deps.md) — Workspace dependency inheritance
- [proj-workspace-publish](./proj-workspace-publish.md) — Native workspace publishing
- [proj-msrv-declare](./proj-msrv-declare.md) — Declare MSRV in Cargo.toml

## References

- [Cargo Workspace Inheritance docs](https://doc.rust-lang.org/cargo/reference/workspaces.html#the-package-table)
- [RFC 2906 — Workspace package deduplication](https://rust-lang.github.io/rfcs/2906-cargo-workspace-deduplicate.html)
- [proj-workspace-deps](./proj-workspace-deps.md) — Related workspace dependency inheritance
- [proj-workspace-large](./proj-workspace-large.md) — Workspace structure
