# doc-link-types

> Cross-link related public types and operations when the links help readers navigate the API

## Why It Matters

A public API is usually understood as a graph of related concepts rather than one item at a time. Intra-doc links can connect constructors to builders, operations to their error types, iterators to their item semantics, and modules to the types they expose.

Rustdoc validates those targets when documentation is built. That catches many broken references after refactors, but the links themselves do not automatically rewrite their source paths when items move or are renamed.

This rule focuses on **which relationships to link**. See [doc-intra-links](./doc-intra-links.md) for detailed syntax and disambiguation.

## Good: Connect an Operation to Its Result and Error Types

```rust
/// Successful parsing result.
#[derive(Debug, PartialEq, Eq)]
pub struct Parsed {
    pub value: u32,
}

/// Error returned by [`parse`].
#[derive(Debug, PartialEq, Eq)]
pub enum ParseError {
    Empty,
    Invalid,
}

/// Parses a decimal number into [`Parsed`].
///
/// # Errors
///
/// Returns [`ParseError::Empty`] for an empty string and
/// [`ParseError::Invalid`] for invalid decimal input.
pub fn parse(input: &str) -> Result<Parsed, ParseError> {
    if input.is_empty() {
        return Err(ParseError::Empty);
    }

    input
        .parse::<u32>()
        .map(|value| Parsed { value })
        .map_err(|_| ParseError::Invalid)
}

fn main() {
    assert_eq!(parse("42"), Ok(Parsed { value: 42 }));
}
```

The links express the relationships a caller is likely to follow while learning the API.

## Link Builders and Constructed Types Both Ways

```rust
/// Configured client.
#[derive(Debug, PartialEq, Eq)]
pub struct Client {
    timeout_secs: u64,
}

/// Builder used to create a [`Client`].
#[derive(Default)]
pub struct ClientBuilder {
    timeout_secs: Option<u64>,
}

impl Client {
    /// Starts a [`ClientBuilder`].
    pub fn builder() -> ClientBuilder {
        ClientBuilder::default()
    }
}

impl ClientBuilder {
    /// Sets the request timeout used by the resulting [`Client`].
    pub fn timeout_secs(mut self, value: u64) -> Self {
        self.timeout_secs = Some(value);
        self
    }

    /// Builds a [`Client`].
    pub fn build(self) -> Client {
        Client {
            timeout_secs: self.timeout_secs.unwrap_or(30),
        }
    }
}

fn main() {
    let client = Client::builder().timeout_secs(10).build();
    assert_eq!(client.timeout_secs, 10);
}
```

Bidirectional links are useful when users may enter the documentation from either the builder or the final type.

## Link Trait Semantics with a Complete Implementation

```rust
/// Iterator over integers from zero up to an exclusive limit.
pub struct RangeIter {
    current: u32,
    end: u32,
}

impl RangeIter {
    pub fn new(end: u32) -> Self {
        Self { current: 0, end }
    }
}

impl Iterator for RangeIter {
    type Item = u32;

    /// Produces the next [`Iterator::Item`].
    fn next(&mut self) -> Option<Self::Item> {
        if self.current >= self.end {
            return None;
        }
        let value = self.current;
        self.current += 1;
        Some(value)
    }
}

fn main() {
    assert_eq!(RangeIter::new(2).collect::<Vec<_>>(), vec![0, 1]);
}
```

The old example omitted the required `Iterator::Item` associated type, so it failed to compile before rustdoc link behavior was relevant.

## Link Only Publicly Useful Relationships

Do not expose implementation structure merely to create more links. If an internal tokenizer, cache, or helper type is not part of the supported public model, documentation for a high-level parser usually should not direct users into it.

Prefer links to concepts callers can act on:

- constructors and builders;
- returned value and error types;
- related traits users may implement or call;
- alternate operations with meaningful semantic differences;
- feature-gated modules/types when the feature changes available API.

## Module-Level Navigation

Module documentation is a good place for a compact index of the main public concepts:

```rust
pub mod parser {
    //! Parsing primitives.
    //!
    //! - [`Parser`] performs parsing.
    //! - [`Token`] represents one parsed token.

    pub struct Parser;
    pub struct Token(pub String);
}

fn main() {
    let _ = parser::Parser;
    let _ = parser::Token(String::from("name"));
}
```

Avoid maintaining a giant hand-written table of every public item if rustdoc's generated item lists already provide adequate navigation.

## Refactors Still Require Documentation Maintenance

A path such as ``[`crate::parser::Parser`]`` is checked against the current source tree when rustdoc runs. If the type moves to another module, the source link can become broken. Enable rustdoc link checking so refactors fail loudly rather than relying on the false idea that Markdown links rewrite themselves.

```rust
#![deny(rustdoc::broken_intra_doc_links)]

/// Creates a [`std::collections::HashMap`].
pub fn empty_map() -> std::collections::HashMap<String, String> {
    std::collections::HashMap::new()
}

fn main() {
    assert!(empty_map().is_empty());
}
```

## Practical Guidance

- Link the next concept a reader is likely to need.
- Link error/result/builder/trait relationships that clarify the public model.
- Do not link implementation-only details just because a Rust item exists.
- Keep examples complete so unrelated type errors do not hide documentation problems.
- Run rustdoc with broken-link warnings enforced after refactors.

## See Also

- [doc-intra-links](./doc-intra-links.md) - Link syntax and resolution
- [doc-examples-section](./doc-examples-section.md) - Code examples in docs
- [err-doc-errors](./err-doc-errors.md) - Documenting errors
- [lint-deny-correctness](./lint-deny-correctness.md) - Lint settings
