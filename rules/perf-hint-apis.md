# perf-hint-apis

> Use branch hint APIs for hot-path optimization

**Rule**: `perf-hint-apis`

## Why It Matters

Modern CPUs use branch prediction to maintain high instruction throughput. Mispredicted branches cause pipeline stalls. Rust provides stable hint APIs that tell the compiler and CPU about branch likelihood, enabling better code layout and prediction decisions.

Available in stable Rust:
- `std::hint::cold_path` (1.95) — mark a path as cold for code layout
- `std::hint::select_unpredictable` (1.88) — hint that a branch is unpredictable
- `std::hint::assert_unchecked` (1.81) — skip a bounds check unconditionally

## Bad

```rust
// No branch hints — compiler treats both paths equally
fn process_or_error(data: &[u8]) -> Result<(), Error> {
    if data.is_empty() {
        return Err(Error::Empty);
    }
    for &b in data {
        if b == 0 {
            return Err(Error::ZeroByte);
        }
    }
    Ok(())
}

// Predictable hot loop — no hint for the uncommon case
fn lookup(cache: &HashMap<u64, Item>, key: u64) -> Item {
    if let Some(item) = cache.get(&key) {
        item.clone()  // Common case
    } else {
        fetch_from_db(key)  // Rare case, compiler may lay out inline
    }
}
```

## Good

```rust
use std::hint::{cold_path, select_unpredictable, assert_unchecked};

// cold_path: tell compiler the error branch is cold
fn process_or_error(data: &[u8]) -> Result<(), Error> {
    if data.is_empty() {
        cold_path();
        return Err(Error::Empty);
    }
    for &b in data {
        if b == 0 {
            cold_path();
            return Err(Error::ZeroByte);
        }
    }
    Ok(())
}

// cold_path + early return for cache miss
fn lookup(cache: &HashMap<u64, Item>, key: u64) -> Item {
    if let Some(item) = cache.get(&key) {
        return item.clone();
    }
    cold_path();
    fetch_from_db(key)  // Moved to a cold code section
}
```

## select_unpredictable (Rust 1.88+)

For branches that are truly unpredictable (e.g., data-dependent), `select_unpredictable` tells the compiler to use conditional move instructions instead of branches, avoiding branch misprediction penalties:

```rust
use std::hint::select_unpredictable;

// Unpredictable branch: each element's sign is random
fn sum_positives(values: &[i32]) -> i32 {
    let mut sum = 0;
    for &v in values {
        // Without hint: branch, may mispredict
        // With hint: compiler likely uses CMOV
        if select_unpredictable(v > 0) {
            sum += v;
        }
    }
    sum
}

// Practical: binary search with unpredictable comparisons
fn binary_search(haystack: &[u64], needle: u64) -> Option<usize> {
    let mut size = haystack.len();
    let mut base = 0;
    
    while size > 1 {
        let half = size / 2;
        let mid = base + half;
        // Comparison result is unpredictable — hint helps
        base = if select_unpredictable(haystack[mid] <= needle) {
            mid
        } else {
            base
        };
        size -= half;
    }
    
    if !haystack.is_empty() && haystack[base] == needle {
        Some(base)
    } else {
        None
    }
}
```

## assert_unchecked (Rust 1.81+)

`assert_unchecked` tells the compiler that a boolean expression is always true. Use it to eliminate bounds checks when you know the index is valid but the compiler doesn't:

```rust
use std::hint::assert_unchecked;

// SAFETY: `idx` is always < `data.len()` by construction
unsafe fn get_unchecked_trusted(data: &[i32], idx: usize) -> i32 {
    // Without hint: compiler emits bounds check
    // With hint: compiler can elide the check
    assert_unchecked(idx < data.len());
    *data.get_unchecked(idx)
}

// But prefer iterators or array_windows when possible:
fn safe_alternative(data: &[i32]) -> i32 {
    data.array_windows::<2>()
        .map(|&[a, b]| a + b)
        .sum()
    // Zero bounds checks, no unsafe
}
```

## When to Use Each

| API | Since | Use Case | Mechanism |
|-----|-------|----------|-----------|
| `cold_path()` | 1.95 | Error paths, cache misses, rarely-taken branches | Code layout: puts marked path in cold section |
| `select_unpredictable(cond)` | 1.88 | Truly unpredictable branches (binary search, data-dependent) | Compiler emits CMOV or equivalent |
| `assert_unchecked(cond)` | 1.81 | Known-invariant conditions the compiler can't prove | UB if condition is false; enables elision |

## Performance Impact

| Scenario | Without Hint | With Hint |
|----------|-------------|-----------|
| Cold path (rarely taken) | May be inlined in hot section | Moved to .cold section, better I-cache usage |
| Unpredictable branch | Branch misprediction stalls | CMOV/select — no branch, constant latency |
| Known-valid index | Bounds check + branch | No check, load direct |

## See Also

- [perf-black-box-bench](./perf-black-box-bench.md) - black_box benchmarks
- [opt-cold-unlikely](./opt-cold-unlikely.md) - #[cold] attribute
- [opt-likely-hint](./opt-likely-hint.md) - likely/unlikely intrinsics
- [opt-bounds-check](./opt-bounds-check.md) - Bounds check elimination
