# doc-module-inner

> Use `//!` for module-level documentation

## Why It Matters

Inner doc comments (`//!`) document the module itself, not the next item. They appear at the top of module files and describe the module's purpose, contents, and usage patterns. This helps users understand what a module provides before diving into individual items.

Module docs are the first thing users see in `cargo doc` when navigating to a module.

## Bad

```rust
// This module handles authentication
// It provides JWT and session-based auth

mod auth;

pub use auth::*;
```

```rust
// auth.rs
/// Authentication utilities  // Wrong: this documents nothing useful
use std::collections::HashMap;

pub struct Session { /* ... */ }
```

## Good

```rust
//! Authentication and authorization utilities.
//!
//! This module provides multiple authentication strategies:
//!
//! - [`JwtAuth`] - JSON Web Token based authentication
//! - [`SessionAuth`] - Cookie-based session authentication
//! - [`ApiKeyAuth`] - API key authentication for services
//!
//! # Examples
//!
//! ```
//! use my_crate::auth::{JwtAuth, Authenticator};
//!
//! let auth = JwtAuth::new("secret-key");
//! let token = auth.generate_token(&user)?;
//! ```
//!
//! # Feature Flags
//!
//! - `jwt` - Enables JWT authentication (enabled by default)
//! - `sessions` - Enables session-based authentication

use std::collections::HashMap;

pub struct Session { /* ... */ }
```

## Where to Use Inner Docs

| Location | Purpose |
|----------|---------|
| `lib.rs` | Crate-level documentation (appears on crate root) |
| `mod.rs` | Module documentation for directory modules |
| `module.rs` | Module documentation for single-file modules |

## Crate Root Example

```rust
//! # My Awesome Crate
//!
//! `my_crate` provides utilities for handling complex workflows.
//!
//! ## Quick Start
//!
//! ```rust
//! use my_crate::prelude::*;
//!
//! let workflow = Workflow::builder()
//!     .add_step(Step::new("fetch"))
//!     .add_step(Step::new("process"))
//!     .build();
//! ```
//!
//! ## Modules
//!
//! - [`workflow`] - Core workflow engine
//! - [`steps`] - Built-in workflow steps
//! - [`prelude`] - Common imports
//!
//! ## Feature Flags
//!
//! | Feature | Description |
//! |---------|-------------|
//! | `async` | Async workflow execution |
//! | `serde` | Serialization support |

pub mod workflow;
pub mod steps;
pub mod prelude;
```

## Crate Root with include_str

For large crate-level docs, use `#[doc = include_str!("...")]` to embed
a README or separate doc file as the crate root documentation:

```rust
//! # My Awesome Crate
//!
#![doc = include_str!("../README.md")]
```

This keeps `lib.rs` clean while ensuring the README is also the crate
documentation.

> **Caution (Edition 2024)**: When using nested `include_str!` inside
> documentation produced by `include_str!`, paths resolve relative to the
> outermost included file, not the Rust source. See
> [doc-include-str](./doc-include-str.md) for details.

## Feature Flags Section

When using `doc_cfg`, list feature flags at the module level and annotate
items with `#[doc(cfg(feature = "..."))]`:

```rust
//! # Feature Flags
//!
//! | Feature | Description | Default |
//! |---------|-------------|---------|
//! | `async` | Async workflow execution | yes |
//! | `serde` | Serialization support | no |
```

Then in the same crate:

```rust
/// Process items asynchronously.
#[doc(cfg(feature = "async"))]
pub mod async_workflow;
```

Enable this with `docsrs` cfg in your `Cargo.toml`:

```toml
[package.metadata.docs.rs]
all-features = true
rustdoc-args = ["--cfg", "docsrs"]
```

## Lints

Enable `missing_crate_level_docs` to warn when the crate root (`lib.rs`)
lacks documentation:

```rust
#![warn(missing_crate_level_docs)]
```

## Key Sections for Module Docs

1. **Brief description** - One-line summary
2. **Overview** - What the module provides
3. **Examples** - How to use it
4. **Feature flags** - Optional functionality and doc_cfg integration
5. **See Also** - Related modules

## See Also

- [doc-all-public](./doc-all-public.md) - Documenting public items
- [doc-examples-section](./doc-examples-section.md) - Adding examples
- [doc-cargo-metadata](./doc-cargo-metadata.md) - Crate metadata
- [doc-include-str](./doc-include-str.md) - README as crate root docs
- [doc-cfg-patterns](./doc-cfg-patterns.md) - Feature/platform doc annotations
