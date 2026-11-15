# coll-trim-prefix-suffix

> Prefer Rust 1.100 `trim_prefix` / `trim_suffix` when optional boundary removal is clearer than manual slicing

**Rule**: `coll-trim-prefix-suffix`

## Why It Matters

Rust 1.100 stabilizes boundary trimming for strings and slices, plus `Path::trim_prefix`. Unlike `strip_prefix` / `strip_suffix`, which return an `Option` indicating whether a prefix/suffix matched, trimming keeps the original input when no match occurs. These methods avoid off-by-one errors and preserve borrowed subslices without allocating.

## Good: Remove an Optional Affix

```rust
fn main() {
    assert_eq!("https://example.test".trim_prefix("https://"), "example.test");
    assert_eq!("example.test".trim_prefix("https://"), "example.test");
    assert_eq!("frame\r\n".trim_suffix("\r\n"), "frame");
    let bytes = [0_u8, 1, 2, 0];
    assert_eq!(bytes.trim_prefix(&[0_u8][..]), &[1, 2, 0]);
    assert_eq!(bytes.trim_suffix(&[0_u8][..]), &[0, 1, 2]);
}
```

For a **required** prefix, prefer `strip_prefix` plus an explicit error/branch. Trimming silently retains unmatched data, which is wrong for mandatory input validation. Neither operation implies case folding, canonical Unicode normalization, or path security validation.

Use `Path::trim_prefix` for filesystem paths instead of slicing their string representation. Path semantics are component-aware and not interchangeable with string prefix operations.

## See Also

- [api-parse-dont-validate](./api-parse-dont-validate.md) — mandatory input contracts
- [coll-seq-choice](./coll-seq-choice.md) — slices and borrowed views
