# lint-edition-2024

> Track Edition 2024 lints (`unsafe_op_in_unsafe_fn`, `keyword_idents`, etc.)

**Rule**: `lint-edition-2024`

## Why It Matters

Rust Edition 2024 introduces several new lints that catch subtle bugs and enforce modern idioms. Many of these are deny-by-default when the edition is set to `2024`. Without explicit configuration, teams can be surprised by breakage during migration or miss the benefits of new checks.

## Key Edition 2024 Lints

| Lint | Default Level | Effective Since | What It Catches |
|------|--------------|-----------------|-----------------|
| `unsafe_op_in_unsafe_fn` | `deny` | Edition 2024 | Each individual operation inside `unsafe fn` must be in its own `unsafe {}` block |
| `keyword_idents` | `deny` | Edition 2024 | Using new keywords (`gen`, `await`, `try`) as identifiers |
| `anonymous_lifetime_in_impl_trait` | `deny` | Edition 2024 | `impl Trait<'_>` uses must be explicit |
| `if_let_rescope` | `warn` | Edition 2024 | `if let` temporaries that now drop earlier |
| `strict_module_headers` | `warn` | Edition 2024 | Module declarations with inconsistent or missing headers |

## Bad

```toml
# No explicit lint configuration — relying on defaults
[package]
edition = "2024"

# Builds may break unexpectedly for developers on older toolchains
# or team members unaware of Edition 2024 lint changes
```

## Good

```toml
# Explicit workspace lint configuration for Edition 2024
[workspace.lints.rust]
unsafe_op_in_unsafe_fn                 = "deny"
keyword_idents                          = "deny"
anonymous_lifetime_in_impl_trait        = "deny"
if_let_rescope                          = "warn"
strict_module_headers                   = "warn"

[workspace.lints.clippy]
# Edition 2024 makes let_chains stable — prefer if-let chains
# instead of nested if let
style       = "warn"
complexity  = "warn"
```

## `unsafe_op_in_unsafe_fn` Detail

Edition 2024 requires that each unsafe operation inside an `unsafe fn` be wrapped in its own `unsafe {}` block:

```rust
// Edition 2021 — compiles without unsafe blocks inside unsafe fn
unsafe fn read(ptr: *const u8) -> u8 {
    *ptr  // implicitly unsafe
}

// Edition 2024 — each unsafe operation must be explicit
unsafe fn read(ptr: *const u8) -> u8 {
    // SAFETY: Caller guarantees ptr is valid and aligned.
    unsafe { *ptr }
}
```

This makes safety invariants visible at each call site.

## `let_chains` (Stable in Edition 2024)

Edition 2024 stabilizes `let_chains`, enabling chained `if let` expressions:

```rust
// Before (Edition 2021) — verbose nesting
if let Some(a) = x {
    if let Some(b) = y {
        if a < b {
            do_something();
        }
    }
}

// After (Edition 2024) — flat chains
if let Some(a) = x
    && let Some(b) = y
    && a < b
{
    do_something();
}
```

## `if_let_rescope`

Edition 2024 changes the scope of temporaries in `if let` conditions:

```rust
// Temporaries in if let now drop earlier in Edition 2024
if let Some(val) = cache.lock().unwrap().get(&key) {
    // In Edition 2021: lock held for entire block
    // In Edition 2024: lock dropped after the get()
    println!("Found: {}", val);
    // val borrows cache entry that may now be stale in 2024!
}
```

## `strict_module_headers`

```rust
// WARN: missing module documentation
mod internal;  // Should be: /// Internal utilities module

// WARN: inconsistent file module
#[path = "other.rs"]
mod foo;  // Use consistent file naming instead
```

## See Also

- [Edition Guide — Rust 2024](https://doc.rust-lang.org/edition-guide/rust-2024/)
- [Edition 2024 lints announcement](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0.html)
- [let_chains stabilization](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0.html)
- [lint-unsafe-doc](./lint-unsafe-doc.md) — Unsafe documentation requirements
- [lint-lints-table](./lint-lints-table.md) — Lint configuration via `[lints]` table
