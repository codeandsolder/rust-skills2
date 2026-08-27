# perf-array-windows

> Use `<[T]>::array_windows` and `<[T]>::as_chunks` when a compile-time window or chunk size is useful

**Rule**: `perf-array-windows`

## Why It Matters

`slice::windows` and `slice::chunks` yield dynamically sized slices (`&[T]`). When the size is known at compile time, newer APIs can expose that fact in the type system:

- `<[T]>::array_windows::<N>()` (Rust 1.94+) yields overlapping `&[T; N]` windows;
- `<[T]>::as_chunks::<N>()` (Rust 1.88+) returns `(&[[T; N]], &[T])` for non-overlapping chunks plus a remainder.

That can make code clearer and can give the optimizer more static information. It does **not** guarantee a particular number of machine-level bounds checks or automatic vectorization.

## Good: Use the Fixed Shape When the Algorithm Has One

```rust
fn differences(data: &[i32]) -> Vec<i32> {
    data.array_windows::<2>()
        .map(|&[left, right]| right - left)
        .collect()
}

fn sum_four_wide(data: &[i32]) -> i32 {
    let (chunks, remainder) = data.as_chunks::<4>();
    let chunk_sum: i32 = chunks
        .iter()
        .map(|chunk| chunk.iter().sum::<i32>())
        .sum();
    chunk_sum + remainder.iter().sum::<i32>()
}

fn main() {
    assert_eq!(differences(&[2, 5, 9]), vec![3, 4]);
    assert_eq!(sum_four_wide(&[1, 2, 3, 4, 5]), 15);
}
```

The benefit here is explicit shape: destructuring `&[T; N]` states that every yielded item has exactly `N` elements.

## `array_windows::<N>`: Overlapping Fixed-Size Windows

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

`array_windows::<N>()`:

- overlaps adjacent windows;
- yields no items when `N` is larger than the slice;
- panics when `N == 0`;
- returns array references, so callers can destructure the fixed shape directly.

The older `windows(N)` remains appropriate when `N` is chosen at runtime.

## `as_chunks::<N>`: Non-Overlapping Fixed-Size Chunks

```rust
fn decode_words(data: &[u8]) -> (Vec<u32>, &[u8]) {
    let (words, remainder) = data.as_chunks::<4>();
    let decoded = words
        .iter()
        .map(|&bytes| u32::from_le_bytes(bytes))
        .collect();
    (decoded, remainder)
}

fn main() {
    let bytes = [1, 0, 0, 0, 2, 0, 0, 0, 9];
    let (words, remainder) = decode_words(&bytes);
    assert_eq!(words, vec![1, 2]);
    assert_eq!(remainder, &[9]);
}
```

The return type is `(&[[T; N]], &[T])`: a slice of fixed-size arrays plus the tail that did not fill a complete chunk. `N == 0` panics.

Use `chunks_exact(N)` instead when the size is runtime data rather than a const generic.

## API Comparison

| Method | Stable | Item/return shape | Overlap | Size source |
|---|---:|---|---|---|
| `windows(n)` | 1.0 | iterator of `&[T]` | Yes | runtime |
| `chunks(n)` | 1.0 | iterator of `&[T]` | No | runtime |
| `chunks_exact(n)` | 1.31 | iterator of `&[T]` + remainder API | No | runtime |
| `array_windows::<N>()` | 1.94 | iterator of `&[T; N]` | Yes | const generic |
| `as_chunks::<N>()` | 1.88 | `(&[[T; N]], &[T])` | No | const generic |

Choose based on semantics and type shape first, not on an assumed performance ranking.

## Bounds Checks Are Not Countable from Syntax Alone

It is tempting to claim that `windows(3)` performs three bounds checks per window while `array_windows::<3>()` performs zero. That is not a reliable source-level statement. The optimizer can prove bounds in many dynamic-slice patterns, while an iterator implementation can still contain control-flow checks unrelated to indexing.

The fixed-size APIs are useful because the length invariant is represented by the type. If a hot loop matters enough for machine-level differences to matter, inspect optimized code or benchmark it.

## Fixed Shape Can Improve Ergonomics Even Without a Speedup

```rust
fn has_rising_pair(data: &[i32]) -> bool {
    data.array_windows::<2>()
        .any(|&[left, right]| left < right)
}

fn main() {
    assert!(has_rising_pair(&[3, 5, 4]));
}
```

Destructuring communicates the invariant without `window[0]` / `window[1]` indexing and without a conversion such as `try_into::<&[T; N]>()` inside the loop.

## Practical Guidance

- Use `array_windows::<N>` for overlapping windows when `N` is a compile-time constant.
- Use `as_chunks::<N>` for non-overlapping fixed-size blocks plus a remainder.
- Keep `windows`, `chunks`, and `chunks_exact` for runtime sizes or when their API is otherwise clearer.
- Do not promise exact bounds-check counts or SIMD from any source form.
- Benchmark or inspect optimized output before calling one equivalent implementation faster.

## See Also

- [perf-iter-over-index](./perf-iter-over-index.md) - Iteration versus indexing
- [perf-collect-once](./perf-collect-once.md) - Avoid intermediate collections
- [perf-iter-lazy](./perf-iter-lazy.md) - Keep iterator pipelines lazy where appropriate
- [opt-bounds-check](./opt-bounds-check.md) - Bounds-check-sensitive hot loops
