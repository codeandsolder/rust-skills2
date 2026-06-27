# proj-workspace-publish

> Use `cargo publish --workspace` for native workspace publishing (Rust 1.90+)

**Rule**: `proj-workspace-publish`

## Why It Matters

Publishing multiple crates in a workspace historically required either manual ordering by dependency graph (error-prone) or external tools like `cargo-workspaces` or `cargo-release`. Since Rust 1.90+, `cargo publish --workspace` publishes all workspace crates in topological order — root dependencies first, leaf consumers last.

## Bad

```bash
# Manual publish — fragile, easy to mis-order
cd crates/common && cargo publish
cd crates/core && cargo publish
cd crates/cli && cargo publish
cd crates/server && cargo publish

# If crates/core depends on crates/common, and you publish
# core first, the publish fails silently or with confusing errors.
# Or worse: you forgot to bump a dependency and it publishes stale.
```

Manual ordering is error-prone at scale. A forgotten crate or wrong order causes broken publishes, retractions, and yanked versions.

## Good

```bash
# Publish all crates in dependency order automatically
cargo publish --workspace
```

This replaces `cargo-workspaces` for basic use cases. Cargo resolves the dependency graph, builds everything, and publishes from leaves upward.

## Safe Workflow

```bash
# 1. Dry run first — catches packaging errors, missing fields
cargo publish --workspace --dry-run

# 2. Allow dirty — if you have uncommitted Cargo.lock changes
cargo publish --workspace --allow-dirty

# 3. With explicit token
CARGO_REGISTRY_TOKEN=xxx cargo publish --workspace
```

## Excluding Crates from `--workspace`

Control which crates are published with `publish` field:

```toml
# crates/internal/Cargo.toml — never published
[package]
name = "my-internal"
version.workspace = true
publish = false  # Excluded from publish --workspace

# crates/tests/Cargo.toml — only publish to specific registry
[package]
name = "my-test-utils"
version.workspace = true
publish = ["my-private-registry"]

# crates/core/Cargo.toml — publish to crates.io
[package]
name = "my-core"
version.workspace = true
# publish = true (default) — published with --workspace
```

## Per-Crate Version Independence

`cargo publish --workspace` does NOT require shared versioning. Each crate can independently version:

```toml
# Root Cargo.toml
[workspace.package]
edition = "2024"
license = "MIT"
# No version — each crate sets its own

# crates/core/Cargo.toml
[package]
name = "my-core"
version = "0.1.0"  # Independent version

# crates/cli/Cargo.toml
[package]
name = "my-cli"
version = "0.2.0"  # Different version
```

Or share a version via `[workspace.package]`:

```toml
[workspace.package]
version = "0.1.0"

# crates/core/Cargo.toml
[package]
name = "my-core"
version.workspace = true

# crates/cli/Cargo.toml
[package]
name = "my-cli"
version = "0.2.0"  # Local override
```

## Anti-Pattern: Manual Publishing Without Dependency Checking

```bash
# ❌ Manually ordering publishes for a 10-crate workspace
# Easy to miss a dependency bump, publish stale versions,
# or skip a crate entirely.
```

Use `cargo publish --workspace --dry-run` first to verify all crates are ready.

## See Also

- [proj-workspace-deps](./proj-workspace-deps.md) — Workspace dependency inheritance
- [proj-workspace-metadata](./proj-workspace-metadata.md) — Shared package metadata inheritance

## References

- [Rust 1.90.0 Release Notes — cargo publish --workspace](https://blog.rust-lang.org/2025/09/18/Rust-1.90.0/)
- [Cargo docs: publish command](https://doc.rust-lang.org/cargo/commands/cargo-publish.html)
- [Tweag blog: Cargo Package Workspace](https://tweag.io/blog/2025-07-10-cargo-package-workspace/)
- [proj-workspace-deps](./proj-workspace-deps.md) — Workspace dependency inheritance
- [proj-workspace-large](./proj-workspace-large.md) — Workspace structure
