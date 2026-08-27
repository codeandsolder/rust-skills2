# doc-include-str

> Use `#[doc = include_str!("...")]` when an external text file is intentionally part of an item's generated documentation

## Why It Matters

`include_str!` reads a UTF-8 file at compile time and expands to a string literal. Supplying that string to the `doc` attribute lets a crate keep substantial Markdown in a separate file while still rendering it as rustdoc documentation.

This can be useful for crate-level README content, long guides, or intentionally shared examples. It also creates a real build dependency on that file: the path must exist, the content must be valid UTF-8, and edits to the file can cause recompilation when the macro is evaluated.

Do not use external files merely to avoid writing ordinary short doc comments next to the code.

## Crate Documentation from a README

A crate can make a README part of its crate-level rustdoc:

<!-- rust-check: ignore; reason=requires repository README file at the documented path -->
```rust
#![doc = include_str!("../README.md")]

pub fn version() -> &'static str {
    "1.0"
}
```

For an ordinary `include_str!` invocation, the relative path is resolved relative to the Rust source file containing the macro invocation.

The `readme = "README.md"` Cargo package field is separate metadata; it tells Cargo/crates.io which README belongs to the package. It does not itself make that README rustdoc content.

## Long Item Documentation

External Markdown can also document one item:

<!-- rust-check: ignore; reason=requires repository Markdown file at the documented path -->
```rust
#[doc = include_str!("../docs/migrations.md")]
pub fn run_migrations() -> Result<(), std::io::Error> {
    Ok(())
}
```

Use this when maintaining the documentation as a separate Markdown document is actually clearer than keeping it next to the item.

## Shared Documentation Across Items

The same source document can be included at multiple documentation sites:

<!-- rust-check: ignore; reason=requires repository Markdown file at the documented path -->
```rust
#[doc = include_str!("../examples/client_basic.md")]
pub fn create_client() {}

#[doc = include_str!("../examples/client_basic.md")]
pub fn send_request() {}
```

Sharing content avoids duplicated prose, but it can also make the document less specific to each item. Prefer a shared file only when the same text genuinely makes sense in every location.

## Gate Documentation-Only Includes Deliberately

Clippy's `doc_include_without_cfg` restriction lint can flag documentation `include_str!` usage that is evaluated during ordinary non-doc builds. A common pattern is:

<!-- rust-check: ignore; reason=requires repository Markdown file at the documented path -->
```rust
#[cfg_attr(doc, doc = include_str!("../docs/advanced.md"))]
pub mod advanced {}
```

This avoids reading the external documentation file unless the `doc` cfg is active. It is a trade-off, not a universal requirement: documentation metadata can participate in cross-crate rustdoc/inlining behavior, so decide whether the docs must be present outside direct documentation builds before adopting the restriction lint mechanically.

## Edition 2024: Nested Includes Inside Included Markdown Doctests

Edition 2024 changed a specific doctest path-resolution case. Suppose `src/lib.rs` includes `docs/guide.md` as documentation, and that Markdown contains a Rust doctest like:

```text
```rust
let text = include_str!("fixture.txt");
assert!(!text.is_empty());
```
```

In Edition 2024, the doctest's `include_str!("fixture.txt")` is resolved relative to `docs/guide.md`. In earlier editions, such nested doctest includes were resolved relative to the Rust source file that carried the outer doc attribute.

The rule concerns `include!`, `include_str!`, and `include_bytes!` **inside doctests originating from an included Markdown file**. It does not mean that arbitrary Rust attributes written as Markdown text are evaluated as attributes.

## Conditional Documentation Is Separate from Conditional Items

`cfg_attr(doc, doc = ...)` controls whether a documentation attribute is attached. `#[cfg(...)]` controls whether the Rust item exists under that configuration. Keep those decisions separate:

```rust
#[cfg(feature = "network")]
/// Networking support when the `network` feature is enabled.
pub mod network {
    pub fn enabled() -> bool {
        true
    }
}

fn main() {}
```

Whether an external guide should be included only in documentation builds and whether the item itself should exist only under a feature are different API questions.

## Verifying External Documentation

Because the file is part of compilation when the macro is evaluated, broken paths are compile errors. Rustdoc can also run Rust code fences inside included Markdown as doctests when they are part of generated documentation.

For a real crate, verify both documentation construction and doctests:

```bash
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
cargo test --doc
```

This rule corpus cannot provide arbitrary repository-relative fixture files to each generated standalone example, so external-file snippets are explicitly marked `ignore` rather than kept as exact baseline failures.

## Practical Guidance

- Use external docs when they improve maintainability, not merely to move text away from source.
- Remember that ordinary relative `include_str!` paths start from the containing Rust source file.
- Apply the Edition 2024 Markdown-relative rule only to nested includes inside doctests from included Markdown.
- Consider `cfg_attr(doc, ...)` when documentation files should not be evaluated during normal builds, but account for your rustdoc/re-export needs.
- Keep repository-dependent snippets explicitly classified in compile-checking harnesses that do not copy those files.

## See Also

- [doc-module-inner](./doc-module-inner.md) - Crate and module documentation
- [doc-examples-section](./doc-examples-section.md) - Runnable examples
- [doc-cfg-patterns](./doc-cfg-patterns.md) - Conditional documentation patterns
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest changes
- [doc-cargo-metadata](./doc-cargo-metadata.md) - Cargo README metadata
