# own-range-copy

**Rule**: `own-range-copy`

> Use `core::range::Range` (Rust 1.96+) when `Copy` range values are useful; keep `core::ops::Range` for legacy iterator and API interoperability

## Why It Matters

The legacy `core::ops::Range<T>` is an iterator whose value itself carries iteration state and deliberately does not implement `Copy`. That is a design choice, not a language rule saying every `Iterator` must be non-`Copy`.

Rust 1.96 stabilized `core::range::Range<T>`, which separates the range value from legacy iterator semantics and can implement `Copy` when `T: Copy`. This is useful when a range is stored as ordinary data inside another `Copy` type.

## When `Copy` Storage Helps

```rust
use core::range::Range;

#[derive(Clone, Copy)]
struct Span {
    bytes: Range<usize>,
}
```

## Keep Legacy Ranges When Interoperating

Many existing APIs use `core::ops::Range` or `RangeBounds`. Do not churn types solely because the newer range exists.

```rust
fn legacy_api(range: core::ops::Range<usize>) {
    for i in range {
        use_index(i);
    }
}
```

## Key Points

- `core::ops::Range` being non-`Copy` is deliberate legacy iterator design, not a trait-system impossibility.
- Prefer `core::range::Range` when range values are data and `Copy` semantics are actually useful.
- Prefer compatibility over migration churn when surrounding APIs still use `core::ops` ranges.
- Do not claim a performance win without measurement; the primary benefit is ownership/ergonomics.

## See Also

- [perf-copy-range](./perf-copy-range.md) — performance-specific caveat
- [own-copy-small](./own-copy-small.md) — when `Copy` is appropriate
- [`core::range::Range`](https://doc.rust-lang.org/stable/core/range/struct.Range.html)
