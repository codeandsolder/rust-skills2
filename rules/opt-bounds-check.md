# opt-bounds-check

> Structure hot loops so bounds are easy to prove; verify optimized code before using unchecked indexing

## Why It Matters

Safe slice indexing checks that an index is in bounds. In optimized code, rustc/LLVM can often remove redundant checks when loop structure or prior conditions prove the index valid. You cannot reliably count machine-level bounds checks by reading the source, and a different source spelling does not by itself guarantee faster code.

Prefer safe structures that make invariants obvious. If a hot loop is still limited by checks after optimization, verify that with measurements or generated code before introducing `unsafe`.

## Good: Make the Traversal Invariant Obvious

```rust
fn dot_product(left: &[f64], right: &[f64]) -> f64 {
    left.iter()
        .zip(right)
        .map(|(&a, &b)| a * b)
        .sum()
}

fn sum_pairs(data: &[u32]) -> u32 {
    data.array_windows::<2>()
        .map(|&[a, b]| a + b)
        .sum()
}

fn main() {
    assert_eq!(dot_product(&[1.0, 2.0], &[3.0, 4.0]), 11.0);
    assert_eq!(sum_pairs(&[1, 2, 3]), 8);
}
```

`zip` has its own semantics: it stops at the shorter input. Do not replace an indexing loop with `zip` if the old behavior intentionally required equal lengths or panicked on a short second slice.

## Safe Slice APIs Express Bounds Once

Splitting, chunking, and pattern matching can move a length condition to the point where a subslice is created instead of repeating ad-hoc indexing logic throughout the body.

```rust
fn split_header(data: &[u8]) -> Option<([u8; 4], &[u8])> {
    let (header, body) = data.split_at_checked(4)?;
    let header: [u8; 4] = header.try_into().ok()?;
    Some((header, body))
}

fn main() {
    let (header, body) = split_header(&[1, 2, 3, 4, 5]).unwrap();
    assert_eq!(header, [1, 2, 3, 4]);
    assert_eq!(body, &[5]);
}
```

`split_at_checked` stabilized in Rust 1.80 and returns `Option<(&[T], &[T])>` (or the mutable equivalent), not `Result`.

## Fixed-Size Chunks Carry the Length in the Type

`as_chunks::<N>()` (Rust 1.88+) returns complete fixed-size chunks plus a remainder.

```rust
fn sum_four_wide(data: &[f32]) -> f32 {
    let (chunks, remainder): (&[[f32; 4]], &[f32]) = data.as_chunks();
    let full: f32 = chunks
        .iter()
        .map(|chunk| chunk.iter().sum::<f32>())
        .sum();
    full + remainder.iter().sum::<f32>()
}

fn main() {
    assert_eq!(sum_four_wide(&[1.0, 2.0, 3.0, 4.0, 5.0]), 15.0);
}
```

A fixed-size array reference is useful because the length invariant is explicit in the type. That often simplifies code and may help optimization, but it is not a guarantee of a particular instruction sequence.

## Multiple Disjoint Mutable Borrows (Rust 1.86+)

`get_disjoint_mut` safely returns several mutable references at once when every requested index/range is in bounds and the selections do not overlap. It returns a `Result` and performs overlap validation.

```rust
fn swap_first_last(data: &mut [i32]) {
    if data.len() < 2 {
        return;
    }

    let last = data.len() - 1;
    let [first, last] = data.get_disjoint_mut([0, last]).unwrap();
    std::mem::swap(first, last);
}

fn main() {
    let mut data = [1, 2, 3];
    swap_first_last(&mut data);
    assert_eq!(data, [3, 2, 1]);
}
```

For many requested indices, remember that the safe method's overlap checking has a cost (the current implementation documents an `O(n^2)` check). That matters only when `N` itself becomes large enough for the validation to be significant.

## `get_disjoint_unchecked_mut` Is Stable, but Unsafe

The unchecked counterpart also stabilized in Rust 1.86. It skips the bounds/overlap validation, so **all** indices/ranges must be in bounds and pairwise non-overlapping. Merely checking `i != j` is insufficient if either index can be out of range.

```rust
fn swap_known_indices(data: &mut [i32], i: usize, j: usize) {
    assert!(i < data.len());
    assert!(j < data.len());
    assert!(i != j);

    // SAFETY: both indices are in bounds and the assertions prove they differ,
    // so the two selected elements cannot overlap.
    let [left, right] = unsafe { data.get_disjoint_unchecked_mut([i, j]) };
    std::mem::swap(left, right);
}

fn main() {
    let mut data = [10, 20, 30];
    swap_known_indices(&mut data, 0, 2);
    assert_eq!(data, [30, 20, 10]);
}
```

Use the safe method unless profiling shows its validation is material and the unchecked preconditions are straightforward to prove and maintain.

## `get_unchecked` Is a Last-Resort Optimization Boundary

Unchecked indexing is sound only when the index is guaranteed in bounds for every execution reaching the access. Keep the proof immediately adjacent to the unsafe operation.

```rust
fn prefix_sum(data: &[u32], count: usize) -> u32 {
    assert!(count <= data.len());

    let mut sum = 0;
    for index in 0..count {
        // SAFETY: index < count <= data.len().
        sum += unsafe { *data.get_unchecked(index) };
    }
    sum
}

fn main() {
    assert_eq!(prefix_sum(&[1, 2, 3, 4], 3), 6);
}
```

This source is not automatically faster than `data[..count].iter().sum()`. The safe version is usually the better starting point because the compiler may already eliminate equivalent checks.

## Do Not Infer Assembly from Source Syntax

Statements such as “`data[i]` means one bounds check per iteration” or “iterators have no bounds checks” are too strong. Optimization can hoist, merge, or eliminate checks, and iterator adapters have their own control flow.

For a hot function:

1. benchmark a realistic workload in release mode;
2. inspect optimized assembly/IR when necessary to explain the result;
3. try a safe structural rewrite (`zip`, fixed chunks, pre-slicing, explicit length checks);
4. use unchecked access only when the remaining check is demonstrated to matter.

## Bounds Checks Are Often the Correct Cost

Random/user-provided indices need validation somewhere. Safe APIs such as `get` make that explicit and non-panicking.

```rust
fn gather(data: &[u8], indices: &[usize]) -> Vec<u8> {
    indices
        .iter()
        .filter_map(|&index| data.get(index).copied())
        .collect()
}

fn main() {
    assert_eq!(gather(&[10, 20, 30], &[2, 99, 0]), vec![30, 10]);
}
```

Do not remove a necessary validation merely to eliminate a branch; that changes correctness, not just performance.

## Practical Guidance

- Prefer safe iteration/slicing patterns that make bounds obvious to humans and the optimizer.
- Preserve semantics when changing from indexing to `zip` or chunk APIs.
- Remember `split_at_checked` returns `Option`.
- Remember both `get_disjoint_mut` and `get_disjoint_unchecked_mut` are stable since Rust 1.86; only the latter is unsafe.
- Treat exact bounds-check counts and SIMD as properties of optimized output, not syntax.
- Reach for unchecked access only after measurement and with a local, documented proof.

## See Also

- [opt-simd-portable](./opt-simd-portable.md) - Portable SIMD and target features
- [opt-cache-friendly](./opt-cache-friendly.md) - Cache-efficient data layout
- [perf-profile-first](./perf-profile-first.md) - Identify actual hot paths
- [perf-array-windows](./perf-array-windows.md) - Fixed-size window/chunk APIs
