# lint-rustdoc-table

> Keep rustdoc Markdown tables syntactically valid; Rust 1.100 adds `invalid_markdown_table` diagnostics

**Rule**: `lint-rustdoc-table`

## Why It Matters

API documentation is compiled documentation, not arbitrary free-form Markdown. Rust 1.100 introduces rustdoc's `invalid_markdown_table` lint, which helps catch tables that render incorrectly. Broken alignment separators, column counts, and malformed rows make public docs harder to read.

## Good: Valid Header, Divider and Body Cells

```rust
/// Error variants used by a parser.
///
/// | Kind | Meaning |
/// |------|---------|
/// | BadSyntax | Input did not match the grammar |
/// | TooLarge | Declared size exceeds the limit |
pub enum Error {
    BadSyntax,
    TooLarge,
}
```

Run `cargo doc --no-deps` with warnings denied in CI for documentation-facing crates. Do not silence the diagnostic merely to get an ambiguous table rendered.

## See Also

- [doc-examples-section](./doc-examples-section.md) — runnable documentation examples
- [lint-missing-docs](./lint-missing-docs.md) — documentation coverage
