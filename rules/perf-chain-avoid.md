# perf-chain-avoid

> Avoid chain in hot loops

## Why It Matters

`Iterator::chain()` adds overhead for checking which iterator is active on every `.next()` call. In hot loops, this branch prediction overhead can impact performance. For performance-critical code, prefer single iterators or pre-combined collections.

## Bad

```rust
// Chain in hot inner loop
fn process_hot_path(a: &[i32], b: &[i32]) -> i64 {
    let mut sum = 0i64;
    
    // Called millions of times
    for _ in 0..1_000_000 {
        for x in a.iter().chain(b.iter()) {  // Branch every iteration
            sum += *x as i64;
        }
    }
    sum
}

// Chaining multiple small slices in tight loop
fn combine_results(parts: &[&[u8]]) -> Vec<u8> {
    let mut result = Vec::new();
    for part in parts {
        for byte in std::iter::once(&0u8).chain(part.iter()) {
            result.push(*byte);
        }
    }
    result
}
```

## Good

```rust
// Separate loops - branch-free inner loops
fn process_hot_path(a: &[i32], b: &[i32]) -> i64 {
    let mut sum = 0i64;
    
    for _ in 0..1_000_000 {
        for x in a {
            sum += *x as i64;
        }
        for x in b {
            sum += *x as i64;
        }
    }
    sum
}

// Pre-combine outside hot loop
fn combine_results(parts: &[&[u8]]) -> Vec<u8> {
    let mut result = Vec::new();
    for part in parts {
        result.push(0u8);
        result.extend_from_slice(part);
    }
    result
}
```

## core::iter::chain Free Function (Rust 1.91+)

Since Rust 1.91, the free function `core::iter::chain` provides a slightly more ergonomic way to chain two iterators. Performance is identical to the `.chain()` method, but can be clearer in functional pipelines:

```rust
use core::iter::chain;

// Equivalent to a.iter().chain(b.iter())
for x in chain(a.iter(), b.iter()) {
    process(x);
}
```

## When Chain Is Fine

Chain is perfectly acceptable when:

```rust
// One-time iteration, not in hot path
fn collect_all(a: Vec<i32>, b: Vec<i32>) -> Vec<i32> {
    a.into_iter().chain(b).collect()
}

// Lazy evaluation with short-circuit
fn find_in_either(a: &[Item], b: &[Item], target: i32) -> Option<&Item> {
    a.iter().chain(b.iter()).find(|x| x.id == target)
}

// Small number of elements
fn get_prefixes() -> impl Iterator<Item = &'static str> {
    ["Mr.", "Mrs.", "Dr."].iter().copied()
        .chain(["Prof."].iter().copied())
}
```

## Alternative Patterns

### Pre-allocate and Extend

```rust
fn merge_slices(slices: &[&[i32]]) -> Vec<i32> {
    let total: usize = slices.iter().map(|s| s.len()).sum();
    let mut result = Vec::with_capacity(total);
    for slice in slices {
        result.extend_from_slice(slice);
    }
    result
}
```

### Use array_windows for Fixed-Size Windows

For compile-time-size windows, prefer `<[T]>::array_windows` (Rust 1.94+). Unlike chained windows iterators, it produces `&[T; N]` with zero bounds-check overhead:

```rust
// Instead of trying to chain windows
fn sliding_sum(data: &[i32]) -> Vec<i32> {
    data.array_windows::<3>()
        .map(|&[a, b, c]| a + b + c)
        .collect()
}
```

### Use chunk_by for Grouped Patterns

`slice::chunk_by` (Rust 1.77+) replaces chained filter/group patterns:

```rust
// Instead of chaining to group adjacent equal elements
let groups: Vec<_> = data.chunk_by(|a, b| a == b).collect();
```

### Use append for Vecs

```rust
fn combine_vecs(mut a: Vec<i32>, mut b: Vec<i32>) -> Vec<i32> {
    a.append(&mut b);  // Moves elements, no reallocation if a has capacity
    a
}
```

### Flatten Instead of Chain

```rust
// Instead of: a.iter().chain(b.iter()).chain(c.iter())
let all = [a, b, c];
for item in all.iter().flat_map(|slice| slice.iter()) {
    process(item);
}
```

## Performance Impact

| Pattern | Per-Item Overhead |
|---------|-------------------|
| Single iterator | None |
| `chain(a, b)` | 1 branch per item |
| `chain(a, b, c)` | 2 branches per item |
| Nested chains | Compounds |
| Separate loops | None (but code duplication) |

## See Also

- [perf-iter-over-index](./perf-iter-over-index.md) - Prefer iterators
- [perf-extend-batch](./perf-extend-batch.md) - Batch insertions
- [perf-array-windows](./perf-array-windows.md) - Fixed-size windows
- [opt-cache-friendly](./opt-cache-friendly.md) - Cache-friendly patterns
