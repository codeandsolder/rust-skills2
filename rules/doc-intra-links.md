# doc-intra-links

> Use intra-doc links to reference types and items

## Why It Matters

Intra-doc links (`[TypeName]`, `[method](Self::method)`) create clickable references in generated documentation. They're verified at doc-build time, catching broken links early. Unlike URL links, they automatically update when items are renamed or moved. Plain text references become stale and unclickable.

## Bad

```rust
/// Returns the length of the buffer.
/// 
/// See also `capacity()` for the allocated size, and the
/// `Buffer` struct for more details.
pub fn len(&self) -> usize {
    self.data.len()
}

/// Parses the input using std::str::FromStr trait.
/// Check the Error enum for possible failures.
/// 
/// See also: ParseError for error types.
/// Uses the Tokenizer internally.
pub fn parse<T: FromStr>(input: &str) -> Result<T, Error> {
    // ...
}
```

## Good

<!-- rust-check: fragment; reason=extraction artifact: wrapper/context -->
```rust
/// Returns the length of the buffer.
/// 
/// See also [`capacity()`](Self::capacity) for the allocated size, and
/// [`Buffer`] for more details.
pub fn len(&self) -> usize {
    self.data.len()
}

/// Parses the input using [`FromStr`] trait.
/// Check [`Error`] for possible failures.
///
/// [`FromStr`]: std::str::FromStr
pub fn parse<T: FromStr>(input: &str) -> Result<T, Error> {
    // ...
}
```

## Link Syntax

| Syntax | Links To | Example |
|--------|----------|---------|
| `[Name]` | Item in scope | `[Vec]`, `[Option]` |
| `[path::Name]` | Fully qualified item | `[std::vec::Vec]` |
| `[Self::method]` | Method on current type | `[Self::new]` |
| `[Type::method]` | Method on other type | `[String::new]` |
| `[Type::CONST]` | Associated constant | `[usize::MAX]` |
| `[text](path)` | Custom text | `[see here](Self::len)` |
| `[type::Item]` | Associated type | `[Iterator::Item]` |
| `[mod@module_name]` | Module | `[mod@parser]` |

## Common Patterns

### Linking to Self Members

```rust
impl Buffer {
    /// Creates an empty buffer.
    ///
    /// Use [`with_capacity`](Self::with_capacity) if you know the size.
    pub fn new() -> Self { /* ... */ }
    
    /// Creates a buffer with pre-allocated capacity.
    ///
    /// See [`new`](Self::new) for the default constructor.
    pub fn with_capacity(cap: usize) -> Self { /* ... */ }
}
```

### Linking to Trait Items

```rust
/// Implements [`Iterator`] for lazy evaluation.
///
/// The [`Iterator::next`] method advances the cursor.
/// 
/// For parallel iteration, see [`rayon::ParallelIterator`].
pub struct MyIterator { ... }

impl Iterator for MyIterator {
    /// Advances and returns the next value.
    ///
    /// See also [`Iterator::nth`] for skipping elements.
    fn next(&mut self) -> Option<Self::Item> { ... }
}
```

### Linking to Trait Methods

```rust
/// Converts to a string representation.
///
/// This is the implementation of [`Display::fmt`](std::fmt::Display::fmt).
impl Display for MyType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        // ...
    }
}
```

### Related Types and Methods

Link to related items to aid discoverability:

```rust
/// A configuration builder.
///
/// # Example
///
/// ```
/// use my_crate::Config;
///
/// let config = Config::builder()
///     .timeout(30)
///     .build()?;
/// ```
///
/// # Methods
///
/// - [`Config::builder`] - Create a new builder
/// - [`Config::default`] - Create with defaults
///
/// # Related Types
///
/// - [`ConfigBuilder`] - The builder returned by [`Config::builder`]
/// - [`ConfigError`] - Errors that can occur when building
pub struct Config { ... }

impl Config {
    /// Creates a new [`ConfigBuilder`].
    ///
    /// This is equivalent to [`ConfigBuilder::new`].
    pub fn builder() -> ConfigBuilder { ... }
}
```

### Module-Level Documentation with Links

Intra-doc links at the module level create a navigable index:

```rust
//! # Parser Module
//!
//! This module provides parsing utilities.
//!
//! ## Main Types
//!
//! - [`Parser`] - The main parser struct
//! - [`Token`] - Tokens produced by tokenization
//! - [`Ast`] - The abstract syntax tree
//!
//! ## Functions
//!
//! - [`parse`] - Parse a string
//! - [`parse_file`] - Parse a file
//!
//! ## Errors
//!
//! All functions return [`ParseError`] on failure.

pub struct Parser { ... }
pub enum Token { ... }
pub struct Ast { ... }
```

### Disambiguation

When names conflict, use disambiguators:

```rust
/// See [`foo()`](fn@foo) for the function and [`foo`](mod@foo) for the module.

/// Works with [`Error`](struct@Error) struct or [`Error`](trait@Error) trait.
```

| Suffix | Item Type |
|--------|----------|
| `fn@` | Function |
| `mod@` | Module |
| `struct@` | Struct |
| `enum@` | Enum |
| `trait@` | Trait |
| `type@` | Type alias |
| `const@` | Constant |
| `macro@` | Macro |

> **Note**: Rustdoc can auto-disambiguate trait vs derive macro in some cases
> (e.g., both a trait named `Clone` and a `#[derive(Clone)]` macro exist), but
> explicit disambiguators are preferred for clarity and stability.

### Reference-Style Links

For repeated links or long paths:

```rust
/// Parses using [`serde`] with [`Deserialize`] trait.
/// Returns a [`Result`] that may contain [`Error`].
///
/// [`serde`]: https://serde.rs
/// [`Deserialize`]: serde::Deserialize
/// [`Result`]: std::result::Result
/// [`Error`]: crate::Error
```

### Linking to External Crate Types

```rust
/// Works with [`std::collections::HashMap`].
/// See also [`rayon::ParallelIterator`].
```

## Link Resolution

- Links resolve from the **definition module**, not the re-export module
- Relative paths like `super::Parent` work based on the item's definition location
- Use `crate::path::Item` for unambiguous links
- For items in the current module, bare `[Name]` suffices

## Lints and Enforcement

Enable these rustdoc lints to catch linking issues:

```rust
#![deny(broken_intra_doc_links)]
#![warn(private_intra_doc_links)]    // Links to private items
#![warn(redundant_explicit_links)]   // Unnecessary full paths
```

Or in `Cargo.toml`:

```toml
[lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "warn"
redundant_explicit_links = "warn"
```

- **`private_intra_doc_links`** (warn-by-default): warns when an intra-doc link
  targets a private item. Helps avoid linking users to inaccessible items.
- **`redundant_explicit_links`** (warn-by-default): warns when you write
  `[text](path)` where `text` already matches the link target. Write `[path]`
  instead.

## Verification

Enable link checking in CI:

```bash
# Fail the build on any broken link
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps

# Or check link warnings specifically
cargo doc --no-deps 2>&1 | grep "warning: unresolved link"
```

This fails if any intra-doc links are broken.

## See Also

- [doc-all-public](./doc-all-public.md) - Documenting public items
- [doc-examples-section](./doc-examples-section.md) - Adding examples
- [doc-errors-section](./doc-errors-section.md) - Documenting errors
- [doc-module-inner](./doc-module-inner.md) - Module-level documentation
