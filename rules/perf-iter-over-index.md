# perf-iter-over-index

> Prefer iterators over manual indexing

## Why It Matters

Iterators are the idiomatic way to traverse collections in Rust. They enable bounds check elimination, SIMD auto-vectorization, and cleaner code. Manual indexing (`for i in 0..len`) often prevents these optimizations and introduces off-by-one error risks.

## Bad

```rust
// Manual indexing - bounds checked every iteration
fn sum_squares(data: &[i32]) -> i64 {
    let mut sum = 0i64;
    for i in 0..data.len() {
        sum += (data[i] as i64) * (data[i] as i64);
    }
    sum
}

// Index-based iteration with multiple collections
fn dot_product(a: &[f64], b: &[f64]) -> f64 {
    let mut sum = 0.0;
    for i in 0..a.len().min(b.len()) {
        sum += a[i] * b[i];
    }
    sum
}

// Mutating with indices
fn double_values(data: &mut [i32]) {
    for i in 0..data.len() {
        data[i] *= 2;
    }
}
```

## Good

```rust
// Iterator - bounds checks eliminated, SIMD-friendly
fn sum_squares(data: &[i32]) -> i64 {
    data.iter()
        .map(|&x| (x as i64) * (x as i64))
        .sum()
}

// Zip iterators - no manual length handling
fn dot_product(a: &[f64], b: &[f64]) -> f64 {
    a.iter()
        .zip(b.iter())
        .map(|(&x, &y)| x * y)
        .sum()
}

// Mutable iteration
fn double_values(data: &mut [i32]) {
    for x in data.iter_mut() {
        *x *= 2;
    }
}
```

## Fixed-Size Windows with array_windows (Rust 1.94+)

For compile-time-size windows, `<[T]>::array_windows` produces `&[T; N]` with zero bounds-check overhead — a strict improvement over manual `for i in 0..len - n + 1`:

```rust
// Bad: manual indices, bounds-checked
fn moving_avg(data: &[f64]) -> Vec<f64> {
    let mut result = Vec::new();
    for i in 0..data.len().saturating_sub(2) {
        result.push((data[i] + data[i + 1] + data[i + 2]) / 3.0);
    }
    result
}

// Good: array_windows, no bounds checks
fn moving_avg(data: &[f64]) -> Vec<f64> {
    data.array_windows::<3>()
        .map(|&[a, b, c]| (a + b + c) / 3.0)
        .collect()
}
```

## Storing Range Bounds with core::range::Range (Rust 1.96+)

When storing range bounds in structs, `core::range::Range` (1.96+) implements `Copy` because it implements `IntoIterator` instead of `Iterator`:

```rust
use core::range::Range;

#[derive(Clone, Copy)]
struct Chunk {
    offset: Range<usize>,  // Copy! vs core::ops::Range which is not Copy
    label: &'static str,
}

// core::ops::Range implements Iterator, so it can't be Copy
// core::range::Range implements IntoIterator, enabling Copy
```

This is useful when storing range metadata in arrays or Copy-heavy structs without needing a custom wrapper.

## When Indexing Is Needed

Sometimes you genuinely need indices:

```rust
// Need the index for output or processing
for (i, value) in data.iter().enumerate() {
    println!("Index {}: {}", i, value);
}

// Non-sequential access patterns
fn interleave(data: &mut [i32]) {
    let mid = data.len() / 2;
    for i in 0..mid {
        data.swap(i * 2, mid + i);
    }
}
```

## Performance Comparison

| Pattern | Bounds Checks | SIMD Potential | Clarity |
|---------|---------------|----------------|---------|
| `for i in 0..len` | Every access | Limited | Medium |
| `for &x in slice` | None | High | High |
| `.iter().enumerate()` | None | Medium | High |
| `get_unchecked` | None (unsafe) | High | Low |

## Iterator Advantages

```rust
// Chaining operations - single pass
let result: Vec<_> = data.iter()
    .filter(|x| **x > 0)
    .map(|x| x * 2)
    .collect();

// Early termination optimized
let found = data.iter().any(|&x| x == target);

// Parallel iteration (with rayon)
use rayon::prelude::*;
let sum: i64 = data.par_iter().map(|&x| x as i64).sum();
```

## See Also

- [perf-iter-lazy](./perf-iter-lazy.md) - Keep iterators lazy
- [perf-array-windows](./perf-array-windows.md) - Fixed-size windows
- [opt-bounds-check](./opt-bounds-check.md) - Bounds check elimination
- [anti-index-over-iter](./anti-index-over-iter.md) - Anti-pattern
