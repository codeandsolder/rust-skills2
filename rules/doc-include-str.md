# doc-include-str

> Use `#[doc = include_str!("...")]` for embedding external content in documentation

## Why It Matters

`#[doc = include_str!("...")]` embeds the content of an external file
into doc comments at compile time. This enables:

- Using the project README as the crate-level documentation
- Sharing the same examples or prose across multiple items
- Keeping large documentation files separate from source code
- Conditional documentation with `cfg_attr(doc, ...)`

## Bad

```rust
// Duplicated across lib.rs and README — can diverge
//! # My Crate
//!
//! `my_crate` is a fast HTTP client for Rust.
//! It provides async and sync clients.
```

## Good

```rust
//! # My Crate
//!
#![doc = include_str!("../README.md")]
```

The README stays as the single source of truth for both the crate docs
and the GitHub project page.

## Patterns

### Crate Root from README

```rust
// lib.rs
#![doc = include_str!("../README.md")]
```

This makes the README the crate-level documentation. Combine with the
`readme` field in `Cargo.toml`:

```toml
[package]
readme = "README.md"
```

### Shared Examples Across Items

```rust
/// Creates a new client.
///
/// # Examples
///
#[doc = include_str!("../examples/client_basic.md")]
pub fn new() -> Self { ... }

/// Sends a request with the client.
///
/// # Examples
///
#[doc = include_str!("../examples/client_basic.md")]
pub fn send(&self, req: Request) -> Result<Response, Error> { ... }
```

### Conditional Documentation

Use `cfg_attr` with `doc` to include additional content only in docs:

```rust
// Only include the extended feature docs when generating docs
#[cfg_attr(doc, doc = include_str!("../docs/feature-guide.md"))]
pub mod advanced_features;
```

### Long Documentation Files

For large modules, keep docs in separate files:

```rust
//! Database migration utilities.
//!
#![doc = include_str!("../docs/migrations.md")]

pub fn run_migrations() -> Result<(), Error> { ... }
```

## Edition 2024: Nested include Paths

In Edition 2024, when a file included via `include_str!` in a doc comment
itself contains `#[doc = include_str!("...")]`, the path resolves relative
to the **outermost included file**, not the Rust source file.

```rust
// lib.rs
#![doc = include_str!("../README.md")]

// README.md
// ## Quick Start
//
// ```rust
// # use my_crate::*;
// let result = my_crate::do_something();
// ```
//
// <!-- This path is relative to README.md, not lib.rs -->
// #[doc = include_str!("./examples/quick_start.rs")]
```

**Migration from Edition 2021**: If you used nested `include_str!` in
doc comments, verify that paths resolve correctly under Edition 2024.

## Lints

Enable `clippy::doc_include_without_cfg` to warn when `include_str!` in
docs is used without `cfg_attr(doc, ...)`:

```toml
# clippy.toml
# (future lint, track upstream stabilization)
```

For now, manually ensure that large `include_str!` docs are not evaluated
in non-doc contexts.

## See Also

- [doc-module-inner](./doc-module-inner.md) - Crate-level documentation
- [doc-examples-section](./doc-examples-section.md) - Examples in docs
- [doc-cfg-patterns](./doc-cfg-patterns.md) - Conditional doc annotations
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Nested include path changes
- [doc-cargo-metadata](./doc-cargo-metadata.md) - README field in Cargo.toml
