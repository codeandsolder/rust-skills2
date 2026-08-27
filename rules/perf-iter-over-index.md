# perf-iter-over-index

> Prefer direct iteration when you are traversing values; use indexing when the index is part of the algorithm

## Why It Matters

Iterators usually express sequential traversal more directly than a manual `0..len` loop and avoid common off-by-one mistakes. They also give the optimizer useful structure, but Rust does **not** promise that an iterator form has no bounds checks, auto-vectorizes, or outperforms equivalent indexing.

Choose the representation that states the algorithm clearly, then inspect or benchmark hot code when the difference matters.

## Good: Traverse Values Directly

```rust
fn sum_squares(data: &[i32]) -> i64 {
    data.iter()
        .map(|&value| i64::from(value) * i64::from(value))
        .sum()
}

fn dot_product(left: &[f64], right: &[f64]) -> f64 {
    left.iter()
        .zip(right)
        .map(|(&a, &b)| a * b)
        .sum()
}

fn double_values(data: &mut [i32]) {
    for value in data {
        *value *= 2;
    }
}

fn main() {
    assert_eq!(sum_squares(&[2, 3]), 13);
    assert_eq!(dot_product(&[1.0, 2.0], &[3.0, 4.0]), 11.0);

    let mut values = [1, 2, 3];
    double_values(&mut values);
    assert_eq!(values, [2, 4, 6]);
}
```

`zip` intentionally stops at the shorter input. That is not semantically identical to indexing over `left.len()` and allowing a short `right` slice to panic, so choose it only when truncating to the common length is the intended behavior.

## Use `enumerate` When You Need Both Index and Value

```rust
fn positions_of_zero(data: &[i32]) -> Vec<usize> {
    data.iter()
        .enumerate()
        .filter_map(|(index, &value)| (value == 0).then_some(index))
        .collect()
}

fn main() {
    assert_eq!(positions_of_zero(&[4, 0, 3, 0]), vec![1, 3]);
}
```

This avoids a second lookup merely to recover the value at an index.

## `array_windows` for Typed Fixed-Size Windows (Rust 1.94+)

`<[T]>::array_windows::<N>()` iterates overlapping windows as `&[T; N]`. The fixed-size array type is often more convenient than indexing a dynamic `&[T]`, and it gives the compiler more static shape information. It does not create a language-level guarantee about exact machine instructions or vectorization.

```rust
fn moving_average(data: &[f64]) -> Vec<f64> {
    data.array_windows::<3>()
        .map(|&[a, b, c]| (a + b + c) / 3.0)
        .collect()
}

fn main() {
    assert_eq!(moving_average(&[1.0, 2.0, 3.0, 4.0]), vec![2.0, 3.0]);
}
```

If `N` is larger than the slice, the iterator is empty. `N == 0` panics.

## Copyable Stored Ranges (Rust 1.96+)

The newer `core::range::Range<T>` implements `Copy` when its field type does. That makes it convenient for stored range metadata that should have value semantics.

```rust
use core::range::Range;

#[derive(Clone, Copy)]
struct Chunk {
    offset: Range<usize>,
    label: &'static str,
}

fn main() {
    let chunk = Chunk {
        offset: Range { start: 4, end: 8 },
        label: "body",
    };
    let copied = chunk;
    assert_eq!(copied.offset.start, 4);
    assert_eq!(chunk.label, "body");
}
```

Do not explain `Copy` as a consequence of implementing `IntoIterator`; trait implementations do not mechanically imply one another. The legacy `core::ops::Range` also participates in iteration but is not `Copy`.

Also remember that `start..end` syntax still constructs the legacy range type today. Construct or convert the new range explicitly until a future edition changes that syntax.

## When Indexing Is the Right Model

Indexing is appropriate when positions, offsets, strides, permutations, or random access are part of the algorithm.

```rust
fn every_other(data: &[i32]) -> Vec<i32> {
    (0..data.len())
        .step_by(2)
        .map(|index| data[index])
        .collect()
}

fn main() {
    assert_eq!(every_other(&[10, 20, 30, 40, 50]), vec![10, 30, 50]);
}
```

Do not contort position-sensitive code into iterator adapters merely to satisfy a slogan.

## Bounds Checks and Vectorization Are Optimizer Questions

A source-level table claiming “iterator = no bounds checks” or “indexing = one check per access” is too strong. LLVM/rustc can eliminate checks from indexed loops when it proves the bounds, and iterator implementations can still contain checks or branches depending on the adapter and monomorphized code.

For a genuinely hot loop:

1. benchmark the realistic workload;
2. inspect optimized assembly or LLVM IR if the reason is unclear;
3. change the source structure only when the evidence points to a useful improvement;
4. reach for unsafe unchecked indexing only after safe alternatives fail and the invariant is simple enough to audit.

## Practical Guidance

- Iterate values directly when the values—not their positions—are what the algorithm needs.
- Use `zip` only when its “stop at the shorter input” semantics are correct.
- Use `enumerate` when both position and value matter.
- Prefer `array_windows::<N>` when a compile-time fixed window type simplifies the code.
- Use indexing freely for genuine positional/random-access algorithms.
- Treat bounds-check elimination and SIMD as measured code-generation properties, not syntax guarantees.

## See Also

- [perf-iter-lazy](./perf-iter-lazy.md) - Keep iterator pipelines lazy where appropriate
- [perf-array-windows](./perf-array-windows.md) - Fixed-size windows and chunks
- [opt-bounds-check](./opt-bounds-check.md) - Bounds-check-sensitive hot loops
- [anti-index-over-iter](./anti-index-over-iter.md) - Avoid pointless index-only traversal
- [own-range-copy](./own-range-copy.md) - New and legacy range types
