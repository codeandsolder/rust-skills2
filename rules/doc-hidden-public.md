# doc-hidden-public

> Use `#[doc(hidden)]` only when a public item must remain callable but should be omitted from normal generated documentation

## Why It Matters

`#[doc(hidden)]` changes **documentation visibility**, not Rust visibility. If an item is `pub`, downstream code can still name and use it even when rustdoc omits it from normal output. Hiding an item therefore does not turn it into implementation-private code and does not erase compatibility concerns around changing or removing it.

This attribute is most useful for deliberately public support surface that end users are not expected to discover directly: macro plumbing, generated helpers, compatibility shims, or implementation-oriented re-exports that must cross a crate boundary.

Do not use it to conceal an awkward public API instead of designing or documenting that API properly.

## Good: Public Support Surface Hidden from Normal Docs

```rust
#[doc(hidden)]
pub mod __macro_support {
    pub fn normalize(value: &str) -> String {
        value.trim().to_ascii_lowercase()
    }
}

pub fn normalized_name(value: &str) -> String {
    __macro_support::normalize(value)
}

fn main() {
    assert_eq!(normalized_name("  Alice "), "alice");

    // The hidden item is still public Rust API and remains callable.
    assert_eq!(__macro_support::normalize(" BOB "), "bob");
}
```

Normal rustdoc output can omit `__macro_support`, but the compiler still treats it as a public module.

## Bad: Hiding an API Users Are Expected to Call

```rust
#[doc(hidden)]
pub fn parse_config(text: &str) -> Result<usize, &'static str> {
    if text.is_empty() {
        Err("configuration is empty")
    } else {
        Ok(text.len())
    }
}

fn main() {
    assert_eq!(parse_config("port=8080"), Ok(9));
}
```

If `parse_config` is a supported entry point that users are meant to discover, give it normal documentation instead of making the documentation incomplete.

## Better: Document the Supported Entry Point

```rust
/// Parses configuration text.
///
/// # Errors
///
/// Returns an error when `text` is empty.
pub fn parse_config(text: &str) -> Result<usize, &'static str> {
    if text.is_empty() {
        Err("configuration is empty")
    } else {
        Ok(text.len())
    }
}

fn main() {
    assert_eq!(parse_config("port=8080"), Ok(9));
    assert!(parse_config("").is_err());
}
```

## Common Legitimate Uses

Typical candidates include:

- public helper items emitted or referenced by macros;
- generated implementation details that need a public path for cross-crate expansion;
- compatibility shims kept callable for existing downstream code but intentionally removed from normal discovery paths;
- public re-exports used for implementation plumbing rather than normal user-facing navigation.

Each case should have a concrete reason the item must be public. If no downstream code needs access, ordinary Rust privacy is a stronger and clearer tool than documentation hiding.

## Hiding a Module

```rust
#[doc(hidden)]
pub mod compatibility {
    pub fn legacy_name() -> &'static str {
        "legacy"
    }
}

fn main() {
    assert_eq!(compatibility::legacy_name(), "legacy");
}
```

Applying `#[doc(hidden)]` to the module keeps that support namespace out of normal rendered documentation while leaving its Rust visibility unchanged.

## Re-exports Need Deliberate Treatment

Rustdoc has special behavior around inlining and re-exporting documentation. Do not assume that hiding an item's original definition is a complete strategy for every re-export layout. Inspect the generated documentation for the public path users actually see, especially when `pub use` is part of the design.

## `missing_docs` Is a Separate Policy

Documentation-hiding and documentation lints answer different questions. Configure `missing_docs` according to the crate's lint policy; do not add `#[doc(hidden)]` merely to evade documentation requirements, and do not rely on a hidden item to become semantically private.

## Practical Guidance

- Prefer Rust privacy when an item does not need to be public.
- Use `#[doc(hidden)]` only when public visibility is intentional but normal discoverability is not.
- Remember that downstream code can still use a hidden public item.
- Treat changes to hidden public surface as compatibility changes according to the promises your crate makes.
- Inspect re-exported documentation rather than assuming `doc(hidden)` propagates exactly as desired through every public path.

## See Also

- [doc-all-public](./doc-all-public.md) - Documenting supported public items
- [api-sealed-trait](./api-sealed-trait.md) - Restricting downstream trait implementations
- [lint-missing-docs](./lint-missing-docs.md) - Documentation lint configuration
