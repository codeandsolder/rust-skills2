# perf-array-windows

> Use `<[T]>::array_windows` and `<[T]>::as_chunks` for compile-time-size windows

**Rule**: `perf-array-windows`

## Why It Matters

Standard `.windows(N)` and `.chunks(N)` return `&[T]` slices, which carry runtime bounds-check and length-dynamic overhead. `<[T]>::array_windows` (Rust 1.94+) and `<[T]>::as_chunks` (Rust 1.88+) produce `&[T; N]` references at compile time, eliminating bounds checks entirely and enabling the compiler to auto-vectorize more aggressively.

## Bad

```rust
// .windows(N) returns &[T] — bounds-checked every access
fn sliding_sum(data: &[i32]) -> Vec<i32> {
    data.windows(3)
        .map(|w| w[0] + w[1] + w[2])  // Each index: bounds check
        .collect()
}

// .chunks(N) returns &[T] — same problem
fn batch_process(data: &[f64]) -> f64 {
    data.chunks(4)
        .map(|c| c.iter().sum())
        .sum()
}
```

## Good

```rust
// array_windows::<3>() returns &[i32; 3] — zero bounds checks
fn sliding_sum(data: &[i32]) -> Vec<i32> {
    data.array_windows::<3>()
        .map(|&[a, b, c]| a + b + c)  // Destructuring is free
        .collect()
}

// as_chunks::<4>() returns &[f64; 4] — zero bounds checks
fn batch_process(data: &[f64]) -> f64 {
    let (chunks, remainder) = data.as_chunks::<4>();
    let sum: f64 = chunks.iter().map(|c| c.iter().sum()).sum();
    // Handle remaining elements if necessary
    let tail_sum: f64 = remainder.iter().sum();
    sum + tail_sum
}
```

## API Comparison

| Method | Since | Returns | Bounds Checks | Overlap |
|--------|-------|---------|---------------|---------|
| `.windows(N)` | 1.0 | `&[T]` | Every access | Yes (sliding) |
| `.chunks(N)` | 1.0 | `&[T]` | Every access | No (non-overlapping) |
| `.array_windows::<N>()` | 1.94 | `&[T; N]` | None | Yes (sliding) |
| `.as_chunks::<N>()` | 1.88 | `(&[T; N], &[T])` | None | No (non-overlapping) |
| `.rchunks(N)` | 1.0 | `&[T]` | Every access | No (reverse) |

## Examples

### Sliding Window (array_windows)

```rust
// Moving average with compile-time window size
fn moving_average(data: &[f64]) -> Vec<f64> {
    data.array_windows::<3>()
        .map(|&[a, b, c]| (a + b + c) / 3.0)
        .collect()
}

// Difference array
fn differences(data: &[i32]) -> Vec<i32> {
    data.array_windows::<2>()
        .map(|&[a, b]| b - a)
        .collect()
}
```

### Non-overlapping Chunks (as_chunks)

```rust
// Process 4-element blocks, handle remainder
fn process_blocks(data: &[u8]) -> Vec<u32> {
    let (blocks, remainder) = data.as_chunks::<4>();
    let mut result: Vec<u32> = blocks.iter()
        .map(|&[a, b, c, d]| u32::from_le_bytes([a, b, c, d]))
        .collect();
    
    // Handle remaining 0-3 bytes
    if !remainder.is_empty() {
        let mut buf = [0u8; 4];
        buf[..remainder.len()].copy_from_slice(remainder);
        result.push(u32::from_le_bytes(buf));
    }
    result
}
```

### Combination with Other Iterators

```rust
// array_windows chains naturally with other iterator adapters
let result: Vec<_> = data.array_windows::<2>()
    .enumerate()
    .filter(|(_, &[a, b])| a < b)
    .map(|(i, _)| i)
    .collect();
```

## Performance

| Method | Bounds Checks | Auto-Vectorization | Memory Layout |
|--------|---------------|-------------------|---------------|
| `windows(3)` | 3 per window | Hindered | `&[T]` dynamic |
| `array_windows::<3>()` | 0 per window | Enabled | `&[T; 3]` fixed |
| `chunks(4)` | Per access | Hindered | `&[T]` dynamic |
| `as_chunks::<4>()` | 0 | Enabled | `&[T; 4]` fixed |

## See Also

- [perf-iter-over-index](./perf-iter-over-index.md) - Prefer iterators over indexing
- [perf-collect-once](./perf-collect-once.md) - Avoid intermediate collections
- [perf-iter-lazy](./perf-iter-lazy.md) - Keep iterators lazy
- [opt-bounds-check](./opt-bounds-check.md) - Bounds check elimination
