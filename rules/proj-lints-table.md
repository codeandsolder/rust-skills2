# proj-lints-table

> Use `[lints]` / `[workspace.lints]` for centralized lint configuration

**Rule**: `proj-lints-table`

## Why It Matters

RFC 3389 (stable since Rust 1.74+) provides native `[lints]` and `[workspace.lints]` tables in Cargo.toml. This replaces `RUSTFLAGS`, `.cargo/config.toml`, and `clippy.toml` for most lint configuration. Centralizing lints in the manifest keeps configuration visible, version-controlled, and inheritable across workspace members.

## Bad

```toml
# RUSTFLAGS or .cargo/config.toml — invisible, hard to maintain
# RUSTFLAGS="-D unsafe_code -W missing_docs"

# Or clippy.toml — separate file, easy to forget
# clippy.toml:
# disallowed-macros = ["unwrap", "expect"]
```

Lint configuration scattered across files is hard to discover, hard to enforce in CI, and cannot be inherited by workspace members.

## Good

```toml
# Root Cargo.toml — workspace-wide lints
[workspace.lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"
missing_copy_implementations = "warn"

[workspace.lints.clippy]
all = "warn"
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "deny"
wildcard_imports = "deny"
large_enum_variant = "warn"

[workspace.lints.rustdoc]
missing_crate_level_docs = "warn"
broken_intra_doc_links = "deny"

# crates/core/Cargo.toml
[package]
name = "my-core"
version.workspace = true

[lints]
workspace = true  # Inherit all workspace lints
```

## Section Structure

```toml
[lints.rust]       # rustc built-in lints (unsafe_code, missing_docs, etc.)
[lints.clippy]     # clippy lints (all, pedantic, unwrap_used, etc.)
[lints.rustdoc]    # rustdoc lints (missing_crate_level_docs, broken_intra_doc_links, etc.)
```

## Override Per-Crate

It is a **hard error** to specify `lints.workspace = true` alongside per-crate lint overrides in the same `[lints]` table (cargo#13157):

```toml
# ❌ Hard error: cannot mix workspace = true with overrides
[lints]
workspace = true
clippy.pedantic = "allow"  # Error!
```

The workaround is to use crate-level attributes in `lib.rs` or `main.rs`:

```rust
// src/lib.rs — override inherited workspace lints
#![allow(clippy::pedantic)]
#![allow(clippy::large_enum_variant)]
#![allow(missing_docs)]
```

Cargo issue [#13157](https://github.com/rust-lang/cargo/issues/13157) is still open as a feature request (status: `S-needs-design`).

## Severity Levels

| Level | Effect |
|-------|--------|
| `forbid` | Error, cannot be overridden |
| `deny` | Error |
| `warn` | Warning |
| `allow` | Suppress |
| `{ level = "...", priority = -1 }` | Set with priority (lower = overridable) |

## Complete Example

```toml
# Root Cargo.toml
[workspace]
members = ["crates/*"]
resolver = "3"

[workspace.package]
version = "0.1.0"
edition = "2024"
license = "MIT"

[workspace.dependencies]
# ...dependencies

[workspace.lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"
missing_copy_implementations = "warn"
trivial_casts = "warn"
trivial_numeric_casts = "warn"
unused_extern_crates = "warn"
unused_import_braces = "warn"
unused_lifetimes = "warn"
unused_qualifications = "warn"

[workspace.lints.clippy]
all = "warn"
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
wildcard_imports = "deny"

[workspace.lints.rustdoc]
missing_crate_level_docs = "warn"
broken_intra_doc_links = "deny"

# crates/my-crate/Cargo.toml
[package]
name = "my-crate"
version.workspace = true
edition.workspace = true

[lints]
workspace = true
```

## Migration from clippy.toml

```toml
# Before: clippy.toml
# disallowed-macros = ["unwrap", "expect"]
# too-many-arguments-threshold = 10

# After: Root Cargo.toml
[workspace.lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
too_many_arguments = "warn"
```

## Known Limitation

Some clippy configuration flags have no `[lints.clippy]` equivalent (e.g., `allow-unwrap-in-tests` in `clippy.toml`). For those, `clippy.toml` may still be needed alongside the manifest lints.

## See Also

- [lint-lints-table](./lint-lints-table.md) — Canonical lint table configuration
- [proj-workspace-deps](./proj-workspace-deps.md) — Workspace dependency inheritance
- [proj-workspace-metadata](./proj-workspace-metadata.md) — Shared package metadata inheritance

## References

- [RFC 3389 — Manifest Lints](https://rust-lang.github.io/rfcs/3389-manifest-lint.html)
- [Cargo docs: The lints section](https://doc.rust-lang.org/cargo/reference/manifest.html#the-lints-section)
- [Clippy configuration via Cargo](https://doc.rust-lang.org/clippy/configuration.html#configuring-clippy-via-cargotoml)
- [proj-workspace-deps](./proj-workspace-deps.md) — Workspace dependency inheritance
- [lint-deny-correctness](./lint-deny-correctness.md) — Lint configuration patterns
