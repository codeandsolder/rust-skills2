# own-range-copy

**Rule**: `own-range-copy`

> Prefer `core::range::Range` (Rust 1.96+, `Copy`) over `core::ops::Range` in new code when the range needs to be `Copy`

## Why It Matters

`core::ops::Range<T>` does not implement `Copy` (it contains a `Bound` enum internally). Rust 1.96 introduced `core::range::Range<T>` as a `Copy`-compatible replacement, enabling `#[derive(Copy)]` on types that contain ranges.

## Bad

```rust
use core::ops::Range;

// Cannot derive Copy — Range<usize> is not Copy
#[derive(Clone, Copy)]
struct Span(Range<usize>);
// ERROR: the trait `Copy` cannot be implemented for this type
```

## Good

```rust
use core::range::Range;

// Range<usize> is Copy — enables Copy on containing types
#[derive(Clone, Copy)]
struct Span(Range<usize>);

// Works for any T: Copy (u32, i64, usize, etc.)
#[derive(Clone, Copy)]
struct Chunk {
    offset: Range<u64>,
    length: Range<u32>,
}
```

## Usage with Slices

```rust
// core::range::Range implements SliceIndex just like ops::Range
fn extract(data: &[u8], range: Range<usize>) -> &[u8] {
    &data[range]
}

let span = Span(Range { start: 2, end: 6 });
let items = extract(&[1, 2, 3, 4, 5, 6, 7], span.0);
// items == [3, 4, 5, 6]
```

## When to Use Which

| Use Case | Type |
|----------|------|
| New code with `Copy`-containing types | `core::range::Range` |
| Code that needs `RangeBounds` trait (all range types) | `core::ops::Range` or keep existing |
| Interop with existing APIs expecting `ops::Range` | `core::ops::Range` (or convert) |
| Hot paths in `Copy`-heavy code | `core::range::Range` |

## Converting Between Range Types

```rust
use core::ops::Range as OpsRange;
use core::range::Range as CopyRange;

let ops: OpsRange<usize> = 0..10;
// Both types can be constructed the same way
let copy: CopyRange<usize> = CopyRange { start: 0, end: 10 };
```

## Cross-Reference

See [own-copy-small](own-copy-small.md) for more on when to implement `Copy` and other types that recently became `Copy`.

## See Also

- [perf-copy-range](./perf-copy-range.md) — Copy-compatible range storage
- [perf-array-windows](./perf-array-windows.md) — Compile-time-size window iteration
- [own-copy-small](./own-copy-small.md) — When to implement Copy on types

## References

- [Rust 1.96.0 release notes](https://blog.rust-lang.org/2026/05/28/Rust-1.96.0.html)
- [`core::range::Range`](https://doc.rust-lang.org/stable/core/range/struct.Range.html)
- [own-copy-small](own-copy-small.md) — Copy type guidelines
- [own-slice-over-vec](own-slice-over-vec.md) — Slice-based APIs
