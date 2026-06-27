# lint-lints-table

> Use the `[lints]` table in `Cargo.toml` for canonical lint configuration (Rust 1.74+)

**Rule**: `lint-lints-table`

## Why It Matters

The `[lints]` table in `Cargo.toml` (Rust 1.74+) is the canonical way to configure lints. It replaces inner attributes like `#![deny(clippy::correctness)]` in `lib.rs` as the primary mechanism. Centralizing lint config in `Cargo.toml` keeps code clean, makes lint policy visible at a glance, and enables workspace inheritance.

## Bad

```rust
// Scattered across lib.rs, main.rs, mod.rs files
#![deny(clippy::correctness)]
#![warn(clippy::suspicious)]
#![warn(clippy::style)]
#![warn(clippy::complexity)]
#![warn(clippy::perf)]
```

## Good

```toml
# Cargo.toml — single source of truth
[lints.rust]
unsafe_code = "deny"

[lints.clippy]
# === Baseline categories ===
correctness = { level = "deny", priority = -1 }
suspicious  = { level = "deny", priority = -1 }
style       = { level = "warn", priority = -1 }
complexity  = { level = "warn", priority = -1 }
perf        = { level = "warn", priority = -1 }

# === Individual overrides (higher priority) ===
unwrap_used           = "deny"
expect_used           = "warn"
dbg_macro             = "deny"
print_stdout          = "warn"

[lints.rustdoc]
broken_intra_doc_links   = "deny"
private_intra_doc_links  = "warn"
```

## Priority System

Since Rust 1.74, lint levels support a `priority` field. Lower values win when multiple configs apply the same lint. Use `priority = -1` for category-level configs so individual lint overrides (which default to `priority = 0`) take precedence:

```toml
[lints.clippy]
# Category: lower priority so individual lints can override
pedantic = { level = "warn", priority = -1 }

# Individual lint: higher priority (0, the default) wins
missing_errors_doc = "allow"   # Overrides pedantic for this lint
```

## Baseline Configuration

```toml
[lints.rust]
# Always on
unsafe_code = "deny"
missing_debug_implementations = "warn"

[lints.clippy]
correctness = { level = "deny", priority = -1 }
suspicious  = { level = "deny", priority = -1 }
style       = { level = "warn", priority = -1 }
complexity  = { level = "warn", priority = -1 }
perf        = { level = "warn", priority = -1 }
```

## Workspace Inheritance

```toml
# Root workspace Cargo.toml
[workspace.lints.clippy]
correctness = "deny"
suspicious  = "deny"
style       = "warn"

# Member Cargo.toml
[lints]
workspace = true
```

> **Note**: When using `lints.workspace = true`, member crates cannot override individual lints in their `Cargo.toml` (see [Cargo issue #13157](https://github.com/rust-lang/cargo/issues/13157)). Use `#![allow(...)]` in code for per-crate exceptions instead.

## Migrating from Inner Attributes

```diff
- #![deny(clippy::correctness)]
- #![warn(clippy::suspicious)]
- #![warn(clippy::style)]
- #![warn(clippy::complexity)]
- #![warn(clippy::perf)]
+ # In Cargo.toml [lints.clippy] table
+ correctness = "deny"
+ suspicious  = "warn"
+ style       = "warn"
+ complexity  = "warn"
+ perf        = "warn"
```

## See Also

- [RFC 3389 — Manifest Lints](https://rust-lang.github.io/rfcs/3389-manifest-lint.html)
- [Cargo Documentation — Lints table](https://doc.rust-lang.org/cargo/reference/manifest.html#the-lints-section)
- [Cargo issue #13157 — workspace lint override limitation](https://github.com/rust-lang/cargo/issues/13157)
- [lint-workspace-lints](./lint-workspace-lints.md) — Workspace-level lint configuration
