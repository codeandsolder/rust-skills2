# perf-copy-range

> Treat `Copy` ranges as an ownership and ergonomics choice, not an automatic performance optimization

## Why It Matters

Rust 1.96's `core::range::Range<T>` can be `Copy` when `T: Copy`, which can simplify small data structures that store ranges by value. But `Copy` does not by itself prove faster code, eliminate all references, or guarantee better generated machine code.

Use the newer range where its value semantics make an API or data structure clearer. Benchmark before presenting the choice as a hot-path optimization.

## Example

```rust
use core::range::Range;

#[derive(Clone, Copy)]
struct TokenSpan {
    bytes: Range<usize>,
}
```

This can make passing and storing `TokenSpan` convenient. Whether it improves performance depends on the surrounding code and optimizer.

## Interoperability Matters

Existing APIs frequently accept `core::ops::Range` or `RangeBounds`. Conversions or adapter code may cost more complexity than any hypothetical micro-optimization.

## Key Points

- Choose `core::range::Range` for useful `Copy` value semantics.
- Do not claim that `Iterator` inherently prevents `Copy`.
- Do not claim automatic speedups from the type change.
- Measure hot paths and keep API compatibility in view.

## See Also

- [own-range-copy](./own-range-copy.md) — canonical ownership guidance
- [own-copy-small](./own-copy-small.md) — `Copy` design
