# doc-all-public

> Document the public API with rustdoc comments

## Why It Matters

Documentation is part of a library's interface. Publicly exposed types, fields, variants, traits, methods, functions, constants, and statics should explain the contract callers need in order to use them correctly without reading the implementation.

Use `///` for item documentation and `//!` for crate/module documentation. The goal is useful API documentation, not comments that merely repeat the identifier.

## Bad

<!-- rust-check: compile -->
```rust
use std::time::Duration;

pub struct Connection;
pub struct ConnectError;

// Public API with no user-facing documentation.
pub struct Config {
    pub timeout: Duration,
    pub retries: u32,
    pub base_url: String,
}

pub fn connect(_config: Config) -> Result<Connection, ConnectError> {
    Ok(Connection)
}

pub enum Status {
    Pending,
    Active,
    Failed,
}
```

This code is valid Rust; the problem is that callers cannot learn the API contract from generated documentation.

## Good

<!-- rust-check: compile -->
```rust
use std::time::Duration;

/// An established service connection.
pub struct Connection;

/// Failure to establish a service connection.
pub struct ConnectError;

/// Configuration used when establishing a service connection.
pub struct Config {
    /// Maximum time to wait for an operation before timing out.
    pub timeout: Duration,

    /// Maximum number of retry attempts after a transient failure.
    pub retries: u32,

    /// Base URL used for service requests.
    pub base_url: String,
}

/// Establishes a service connection using `config`.
///
/// # Errors
///
/// Returns [`ConnectError`] when the connection cannot be established.
pub fn connect(_config: Config) -> Result<Connection, ConnectError> {
    Ok(Connection)
}

/// Current state of a job.
pub enum Status {
    /// Waiting to be processed.
    Pending,

    /// Currently being processed.
    Active,

    /// Processing failed and will not be retried.
    Failed,
}
```

## What to Document

Document the information that is part of the caller-visible contract:

| Item | Useful documentation |
|------|----------------------|
| Struct / enum | Purpose, invariants, important usage constraints |
| Public field | Meaning, units, accepted values |
| Enum variant | When the state occurs and what attached data means |
| Function / method | Behavior, important parameter semantics, return value |
| Fallible function | `# Errors` conditions when useful |
| Panicking function | `# Panics` conditions when useful |
| Unsafe API | `# Safety` requirements |
| Trait | Implementor contract and semantic expectations |
| Constant / static | Meaning, units, and any stability assumptions |

Do not require an example section on every trivial item. Examples are valuable when they clarify usage that the signature and prose do not make obvious.

## Enforce Public Documentation with `missing_docs`

Rustc provides the allow-by-default `missing_docs` lint for missing documentation on public items. Enable it at a level appropriate for the project:

```rust
#![warn(missing_docs)]

/// A documented public function.
pub fn answer() -> u32 {
    42
}
```

Workspace lint configuration can apply the same policy consistently:

```toml
[workspace.lints.rust]
missing_docs = "warn"
```

For a crate that wants missing public docs to break CI, use `deny` after the existing API has been brought into compliance rather than scattering broad `allow` attributes around the codebase.

## Crate-Level Documentation

`rustdoc::missing_crate_level_docs` is a separate rustdoc-only lint that checks whether the crate root has documentation. A documented library normally starts with `//!` documentation in `lib.rs`.

```rust
//! Utilities for processing service requests.

/// Returns the package name used in diagnostics.
pub fn package_name() -> &'static str {
    "service-utils"
}
```

When invoking rustdoc, the crate can opt into:

```text
#![warn(rustdoc::missing_crate_level_docs)]
```

Do not confuse this rustdoc lint with rustc's `missing_docs` lint.

## Clippy's Private-Item Documentation Lint Is Different

Clippy's `missing_docs_in_private_items` restriction lint extends documentation checking to non-public items. The `clippy.toml` options `missing-docs-in-crate-items` and `missing-docs-allow-unused` configure **that Clippy lint**; they do not change rustc's public `missing_docs` behavior.

Use private-item documentation enforcement only when the project deliberately wants it; it is much noisier than documenting the public API.

## `#[doc(hidden)]` Is Not Privacy

`#[doc(hidden)]` removes an item from normal generated documentation, but it does not make a public item private or erase compatibility obligations. Prefer ordinary Rust visibility when an item is truly internal.

```rust
/// Supported public error type.
pub struct ApiError;

#[doc(hidden)]
pub fn compatibility_shim() -> ApiError {
    ApiError
}
```

A hidden public shim can be appropriate for generated/compatibility machinery, but hiding an ordinary public API is not a substitute for documenting it.

## Private Documentation During Development

`cargo doc --document-private-items` can be useful when inspecting internal architecture without changing visibility or the public documentation policy:

```bash
cargo doc --document-private-items
```

## See Also

- [doc-module-inner](./doc-module-inner.md) - Crate and module documentation
- [doc-examples-section](./doc-examples-section.md) - Useful runnable examples
- [lint-missing-docs](./lint-missing-docs.md) - Lint policy
- [doc-hidden-public](./doc-hidden-public.md) - Semantics of `#[doc(hidden)]`
