# doc-module-inner

> Use inner doc comments (`//!`) to document a crate or module as a whole

## Why It Matters

An outer doc comment (`///`) documents the Rust item that follows it. An inner doc comment (`//!`) documents the item that contains it, so at a crate root it documents the crate and at the start of a module body/file it documents that module.

Module-level documentation is the right place to explain purpose, major concepts, cross-cutting invariants, feature-dependent surface, and a short entry-point example. Individual item docs can then focus on their own contracts.

## Good: Document the Module Itself

```rust
pub mod auth {
    //! Authentication helpers.
    //!
    //! Use [`Session`] to represent an authenticated session.

    /// Authenticated user session.
    #[derive(Debug, PartialEq, Eq)]
    pub struct Session {
        pub user_id: u64,
    }

    impl Session {
        pub fn new(user_id: u64) -> Self {
            Self { user_id }
        }
    }
}

fn main() {
    assert_eq!(auth::Session::new(7).user_id, 7);
}
```

The `//!` text belongs to `auth`; the `///` text belongs to `Session`.

## Crate-Level Documentation

At the top of `lib.rs`, inner docs describe the crate root:

```rust
//! Utilities for working with small counters.
//!
//! # Examples
//!
//! ```
//! let value = 40 + 2;
//! assert_eq!(value, 42);
//! ```

/// Returns the library's example answer.
pub fn answer() -> u32 {
    42
}

fn main() {
    assert_eq!(answer(), 42);
}
```

Crate docs should orient users to the public model rather than duplicate every item's generated listing.

## Where Inner Docs Belong

| Location | What `//!` documents |
|---|---|
| `lib.rs` | the library crate |
| `main.rs` | the binary crate |
| `mod.rs` | that directory module |
| `module.rs` | that file's module |
| inline `mod name { ... }` | the inline module |

Keep inner doc comments with other inner attributes at the beginning of the containing item, before ordinary module items.

## Large Crate Docs with `include_str!`

A large README or guide can become crate-level documentation:

<!-- rust-check: compile -->
```rust
#![doc = include_str!("../README.md")]

pub fn version() -> &'static str {
    "1.0"
}
```

The verifier's generated examples live under `checks/examples/`, so this path resolves to the existing `checks/README.md` and the crate-level `doc` attribute is compile-checked rather than skipped. That proves path/UTF-8 availability and Rust syntax, not that an arbitrary project README is suitable API documentation.

Use README inclusion only when the README is intentionally suitable as API documentation. Marketing/project-installation text and API reference material do not always have the same audience.

For ordinary `include_str!`, the path is relative to the Rust source containing the macro. In Edition 2024, a nested `include!`, `include_str!`, or `include_bytes!` **inside a doctest from included Markdown** resolves relative to that Markdown file; see [doc-include-str](./doc-include-str.md).

## Document Stable Feature-Gated Surface Without Unstable `doc_cfg`

Feature tables in prose are stable and useful regardless of rustdoc's annotation features:

```rust
//! Optional functionality.
//!
//! # Cargo features
//!
//! - `network` enables [`network`] support.

#[cfg(feature = "network")]
pub mod network {
    pub fn enabled() -> bool {
        true
    }
}

fn main() {}
```

The `#[cfg(feature = "network")]` attribute controls whether the module exists. Document the feature's meaning and defaults in module/crate prose so users can understand the API on stable Rust.

## `#[doc(cfg(...))]` Is Still Unstable on Rust 1.98

Do not teach this as an ordinary stable attribute:

```text
#![feature(doc_cfg)]

#[doc(cfg(feature = "network"))]
pub mod network;
```

`#[doc(cfg(...))]` remains behind the unstable `doc_cfg` feature on Rust 1.98. Passing `--cfg docsrs` (for example through docs.rs metadata) only defines a cfg value; it does **not** enable the unstable language/rustdoc feature by itself.

Projects that intentionally build documentation with nightly may opt into `doc_cfg`/related rustdoc features, but stable library guidance should not depend on them unless the nightly documentation toolchain is an explicit project choice.

## docs.rs Configuration Is Build Configuration

`[package.metadata.docs.rs]` can request features, targets, and rustdoc arguments for docs.rs builds. For example, a crate may ask docs.rs to build all features. That controls the documentation build environment; it does not make unstable attributes stable.

Keep these questions separate:

- Which Cargo features should docs.rs enable?
- Which `--cfg` values should rustdoc receive?
- Is the project intentionally using a nightly-only rustdoc feature?

## Lint for Missing Crate-Level Docs

Rustdoc provides a lint for crates with no crate-level documentation:

```rust
#![warn(rustdoc::missing_crate_level_docs)]

//! This crate has crate-level documentation.

pub fn public_api() {}

fn main() {}
```

This is useful as a minimum documentation-policy check. It does not judge whether the crate docs are useful or complete.

## What Good Module Docs Usually Cover

Depending on complexity, module docs can include:

- a one-sentence purpose;
- the main entry-point types/functions;
- important relationships or invariants;
- one representative usage example;
- Cargo feature/platform constraints;
- links to neighboring modules or concepts.

Do not force every module into a fixed template. Small modules need less prose than architectural subsystems.

## Practical Guidance

- Use `//!` for the containing crate/module and `///` for the following item.
- Put cross-cutting context at module level instead of repeating it on every item.
- Treat README inclusion as a content-design decision, not a default.
- Document Cargo feature behavior on stable Rust even when you cannot use unstable `#[doc(cfg)]` annotations.
- Do not claim `--cfg docsrs` enables `doc_cfg`.
- In a compile harness, a deterministic README fixture can keep the repository-relative include example strict while real documentation quality remains a rustdoc concern.

## See Also

- [doc-all-public](./doc-all-public.md) - Documenting public items
- [doc-examples-section](./doc-examples-section.md) - Adding examples
- [doc-cargo-metadata](./doc-cargo-metadata.md) - Crate metadata
- [doc-include-str](./doc-include-str.md) - README/external Markdown docs
- [doc-cfg-patterns](./doc-cfg-patterns.md) - Feature/platform documentation patterns
