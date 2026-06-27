# doc-all-public

> Document all public items with `///` doc comments

## Why It Matters

Public items define your crate's API contract. Without documentation, users must read source code to understand how to use your library. Well-documented APIs reduce support burden, improve adoption, and serve as the primary reference for users.

Rust's `cargo doc` generates beautiful HTML documentation from doc comments, but only if you write them.

## Bad

```rust
pub struct Config {
    pub timeout: Duration,
    pub retries: u32,
    pub base_url: String,
}

pub fn connect(config: Config) -> Result<Connection, Error> {
    // ...
}

pub enum Status {
    Pending,
    Active,
    Failed,
}
```

## Good

```rust
/// Configuration for establishing a connection to the service.
///
/// # Examples
///
/// ```
/// use my_crate::Config;
/// use std::time::Duration;
///
/// let config = Config {
///     timeout: Duration::from_secs(30),
///     retries: 3,
///     base_url: "https://api.example.com".to_string(),
/// };
/// ```
pub struct Config {
    /// Maximum time to wait for a response before timing out.
    pub timeout: Duration,
    
    /// Number of retry attempts for failed requests.
    pub retries: u32,
    
    /// Base URL for all API requests.
    pub base_url: String,
}

/// Establishes a connection using the provided configuration.
///
/// # Errors
///
/// Returns an error if the connection cannot be established
/// or if the configuration is invalid.
pub fn connect(config: Config) -> Result<Connection, Error> {
    // ...
}

/// Represents the current status of a job.
pub enum Status {
    /// Job is waiting to be processed.
    Pending,
    /// Job is currently being processed.
    Active,
    /// Job has failed and will not be retried.
    Failed,
}
```

## What to Document

| Item Type | Required Content |
|-----------|------------------|
| Structs | Purpose, usage example |
| Struct fields | What the field represents |
| Enums | When to use each variant |
| Enum variants | What state it represents |
| Functions | What it does, parameters, return value |
| Traits | Contract and expected behavior |
| Trait methods | Default implementation behavior |
| Type aliases | Why the alias exists |
| Constants | What the value represents |

## Enforcement

Enable the `missing_docs` lint to catch undocumented public items:

```rust
#![warn(missing_docs)]
```

Or in `Cargo.toml` for workspace-wide enforcement:

```toml
[workspace.lints.rust]
missing_docs = "warn"
```

For crate-level documentation, also enable:

```rust
#![warn(missing_crate_level_docs)]  // Warns if crate root is undocumented
```

### Clippy Configuration

Clippy provides additional doc lint configuration in `clippy.toml`:

```toml
# Require docs on all public items (default: false)
missing-docs-in-crate-items = true

# Allow missing docs on re-exports and trivial items (default: false)
missing-docs-allow-unused = false
```

### Documenting Private Items

Use `cargo doc --document-private-items` to generate docs for private items
during development:

```bash
cargo doc --document-private-items --open
```

### Suppressing False Positives

Use `#[allow(missing_docs)]` on items where docs are not useful:

```rust
/// Trivial newtype — purpose is clear from the type name.
#[allow(missing_docs)]
pub struct UserId(pub u64);

// FFI bindings where the C API is the canonical reference.
#[allow(missing_docs)]
pub mod ffi;
```

### Hiding Internal Details

Use `#[doc(hidden)]` to omit implementation details from public docs without
making them private:

```rust
/// Public-facing error type.
pub enum ApiError {
    /// ...
}

// Internal conversion — users don't need to see this.
#[doc(hidden)]
impl From<InternalError> for ApiError {
    fn from(e: InternalError) -> Self {
        // ...
    }
}
```

## See Also

- [doc-module-inner](./doc-module-inner.md) - Module-level documentation
- [doc-examples-section](./doc-examples-section.md) - Adding examples
- [lint-missing-docs](./lint-missing-docs.md) - Enforcing documentation
- [doc-hidden-public](./doc-hidden-public.md) - Hiding internal impl details
