# doc-hidden-public

> Use `#[doc(hidden)]` to omit internal impl details from public docs

## Why It Matters

Public items appear in generated documentation by default, but not all
public items are meant for end-user consumption. Internal implementation
details—conversion impls, helper methods, re-exported dependencies—clutter
the documentation and confuse users. `#[doc(hidden)]` removes them from
the rendered output while keeping them publicly accessible.

## Bad

```rust
/// Everything appears in docs: utility helpers, internal conversions,
/// re-exports — users see too much.
pub struct ApiClient { ... }

// Users don't need to see this internal conversion
impl From<InternalError> for ApiError {
    fn from(e: InternalError) -> Self { /* ... */ }
}

// Internal re-export of a dependency
pub use internal_parser::Utf8Processor;
```

## Good

```rust
/// Public-facing API client.
pub struct ApiClient { ... }

// Internal — users should use the error type directly.
#[doc(hidden)]
impl From<InternalError> for ApiError {
    fn from(e: InternalError) -> Self { /* ... */ }
}

// Internal re-export, documented as such.
/// @hidden
#[doc(hidden)]
pub use internal_parser::Utf8Processor;
```

## When to Use `#[doc(hidden)]`

| Scenario | Example |
|----------|---------|
| Internal `From` / `Into` impls | `From<PrivateError>` on a public error type |
| Internal re-exports | `pub use dep::internal_helper;` |
| Test helpers in non-test modules | `pub fn test_setup() { }` |
| Derive macro helpers | `#[doc(hidden)] pub struct __MyMacroHelper { }` |
| Internal trait impls | `impl SealedTrait for MyType` |
| Legacy API shims | `#[doc(hidden)] pub fn old_api_compat() { }` |

## What NOT to Hide

`#[doc(hidden)` should **not** be used to avoid documenting items users
actually need. If an item is part of the public API, document it properly:

```rust
// Bad: Users need this — document it instead of hiding it
#[doc(hidden)]
pub fn critical_public_api_function() { ... }

// Good: Document the function properly
/// Reads and parses the configuration file.
///
/// # Errors
/// ...
pub fn critical_public_api_function() -> Result<Config, Error> { ... }
```

## `#[doc(hidden)]` on Modules

Applying `#[doc(hidden)]` to a module hides all its contents:

```rust
/// Top-level docs — items in here are public but hidden from docs.
#[doc(hidden)]
pub mod internal {
    pub fn helper() { }
}
```

## Interaction with `#[allow(missing_docs)]`

Items marked `#[doc(hidden)]` typically do not need `#[allow(missing_docs)]`
since they don't appear in generated docs. However, the lint still fires:

```rust
#[doc(hidden)]
#[allow(missing_docs)]  // Suppress the warning on hidden items
pub fn internal_helper() { }
```

## See Also

- [doc-all-public](./doc-all-public.md) - Documenting public items
- [api-sealed-trait](./api-sealed-trait.md) - Sealing traits for internal use
- [lint-missing-docs](./lint-missing-docs.md) - Documentation lint configuration
