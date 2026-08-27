# doc-intra-links

> Use intra-doc links for important relationships that rustdoc should resolve and validate

## Why It Matters

Rustdoc intra-doc links turn documentation references into navigable links to Rust items. Because rustdoc resolves the target when documentation is built, broken relationships can be caught by documentation lints instead of silently remaining stale prose.

They do **not** magically follow arbitrary renames or moves. A source-level rename may make a link stop resolving; the benefit is that rustdoc can report that breakage so the documentation is repaired together with the code.

Use links where navigation helps the reader. Do not turn every mention of a type into link-heavy prose.

## Good: Link the Relationships Readers Need

```rust
/// A growable byte buffer.
#[derive(Default)]
pub struct Buffer {
    data: Vec<u8>,
}

impl Buffer {
    /// Creates an empty [`Buffer`].
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the number of stored bytes.
    ///
    /// See [`Self::capacity`] for allocated capacity.
    pub fn len(&self) -> usize {
        self.data.len()
    }

    /// Returns allocated capacity.
    ///
    /// See [`Self::len`] for the logical length.
    pub fn capacity(&self) -> usize {
        self.data.capacity()
    }

    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
}

fn main() {
    let buffer = Buffer::new();
    assert!(buffer.is_empty());
}
```

The code and link targets are real items rather than pseudocode placeholders.

## Common Link Forms

| Form | Typical target |
|---|---|
| ``[`Name`]`` | an item resolvable in the documentation scope |
| ``[`path::Name`]`` | an explicit path |
| ``[`Self::method`]`` | an associated item on the documented type |
| ``[`Type::method`]`` | an associated item on another type |
| ``[`Iterator::Item`]`` | an associated type |
| ``[custom text][`path::Item`]`` | custom prose with an explicit target |
| ``[`foo()`](fn@foo)`` | a disambiguated function |
| ``[`foo`](mod@foo)`` | a disambiguated module |

Use `crate::...`, `self::...`, or `super::...` when a relative bare name would be ambiguous or fragile.

## Linking Trait Items Requires a Complete Trait Implementation

```rust
/// Iterator over a fixed range of integers.
pub struct Counter {
    next: u32,
    end: u32,
}

impl Counter {
    pub fn new(end: u32) -> Self {
        Self { next: 0, end }
    }
}

impl Iterator for Counter {
    type Item = u32;

    /// Advances this iterator according to [`Iterator::next`].
    fn next(&mut self) -> Option<Self::Item> {
        if self.next == self.end {
            return None;
        }

        let value = self.next;
        self.next += 1;
        Some(value)
    }
}

fn main() {
    assert_eq!(Counter::new(3).collect::<Vec<_>>(), vec![0, 1, 2]);
}
```

The old corpus example omitted `type Item`, so its supposed documentation example failed for an unrelated trait-implementation error.

## Link to Standard-Library Items with Paths When Useful

```rust
/// Returns the first value, following [`Option`] semantics.
///
/// The returned container is [`std::option::Option`].
pub fn first(values: &[u32]) -> Option<u32> {
    values.first().copied()
}

fn main() {
    assert_eq!(first(&[3, 4]), Some(3));
}
```

A fully qualified target can be clearer when a short name could refer to multiple items.

## Disambiguate Name Collisions

Rustdoc supports namespaces/disambiguators when the same textual name could denote different kinds of item:

```rust
pub mod parse {
    pub const NAME: &str = "module";
}

/// See [`parse()`](fn@parse) for the function and [`parse`](mod@parse)
/// for the module.
pub fn parse() -> &'static str {
    "function"
}

fn main() {
    assert_eq!(parse(), "function");
    assert_eq!(parse::NAME, "module");
}
```

Common disambiguators include `fn@`, `mod@`, `struct@`, `enum@`, `trait@`, `type@`, `const@`, and `macro@`.

## Resolution Is Based on Where the Documentation Is Defined

Intra-doc links in an item's documentation resolve from the scope where that documentation is defined. Re-exporting the item elsewhere does not reinterpret the original doc comment as though it had been written in the re-exporting module.

When re-exports are part of the public API, build the final documentation and inspect the paths readers see rather than reasoning only from source layout.

## Reference-Style Links

Long or repeated targets can be defined once:

```rust
/// Converts a value using [`From`].
///
/// [`From`]: std::convert::From
pub fn widen(value: u8) -> u16 {
    u16::from(value)
}

fn main() {
    assert_eq!(widen(7), 7_u16);
}
```

## Lints and Verification

A strong baseline is to deny broken intra-doc links when documentation is built:

```rust
#![deny(rustdoc::broken_intra_doc_links)]

/// See [`std::vec::Vec`].
pub fn documented() {}

fn main() {}
```

Other rustdoc lints, including `private_intra_doc_links` and `redundant_explicit_links`, can refine a project's style policy.

In CI, build the documentation rather than grepping compiler text whose wording can change:

```bash
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
```

## Practical Guidance

- Link important API relationships, not every noun.
- Expect renames and moves to require link maintenance; let rustdoc catch broken targets.
- Prefer `Self::...` for associated items on the current type.
- Use explicit paths or disambiguators when resolution would otherwise be unclear.
- Keep examples valid Rust so trait/type errors do not obscure documentation checks.
- Verify the generated docs for re-export-heavy APIs.

## See Also

- [doc-link-types](./doc-link-types.md) - Cross-linking related API types
- [doc-all-public](./doc-all-public.md) - Documenting public items
- [doc-examples-section](./doc-examples-section.md) - Adding examples
- [doc-module-inner](./doc-module-inner.md) - Module-level documentation
