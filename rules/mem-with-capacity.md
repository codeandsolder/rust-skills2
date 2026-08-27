# mem-with-capacity

> Pre-allocate when you have a useful size bound

## Why It Matters

Growing a `Vec`, `String`, or hash table may require allocating a larger backing store and moving existing contents. When you know a useful lower bound for the final size, reserving it up front can avoid repeated growth work.

Do not confuse **requested allocation size** with **reported capacity**. Rust guarantees that `Vec::with_capacity(n)` asks the allocator for exactly enough bytes for `n` elements, but the allocator may return a larger allocation. Consequently, `Vec::capacity()` is guaranteed to be **at least** `n`, not equal to `n`. Zero-sized element types are another obvious exception to byte-oriented intuition.

## Bad

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn process(i: usize) -> usize { i * 2 }

let mut results = Vec::new();
for i in 0..1000 {
    results.push(process(i));
}

let words = ["alpha", "beta", "gamma"];
let mut output = String::new();
for word in words {
    output.push_str(word);
    output.push(' ');
}

let pairs = [("a", 1), ("b", 2), ("c", 3)];
let mut map = HashMap::new();
for (k, v) in pairs {
    map.insert(k, v);
}
```

These are all correct. They are only candidates for pre-allocation when growth cost matters and a useful size estimate is available.

## Good

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn process(i: usize) -> usize { i * 2 }

let mut results = Vec::with_capacity(1000);
for i in 0..1000 {
    results.push(process(i));
}
assert!(results.capacity() >= 1000);

let words = ["alpha", "beta", "gamma"];
let estimated_len: usize = words.iter().map(|w| w.len() + 1).sum();
let mut output = String::with_capacity(estimated_len);
for word in words {
    output.push_str(word);
    output.push(' ');
}
assert_eq!(output.len(), estimated_len);

let pairs = [("a", 1), ("b", 2), ("c", 3)];
let mut map = HashMap::with_capacity(pairs.len());
for (k, v) in pairs {
    map.insert(k, v);
}
assert!(map.capacity() >= 3);
```

## `Vec` Capacity Guarantees

```rust
let v: Vec<u64> = Vec::with_capacity(100);
assert!(v.capacity() >= 100);

let units: Vec<()> = Vec::with_capacity(100);
assert_eq!(units.capacity(), usize::MAX);
```

`Vec::with_capacity(n)` requests storage for exactly `n` elements from the allocator, but the allocator is permitted to provide more. If the actual capacity matters, query `capacity()`.

## Reserve Methods

```rust
let mut v = Vec::with_capacity(8);
v.extend(0..8);

// Ensure room for at least 16 additional elements beyond the current length.
v.reserve(16);
assert!(v.capacity() >= v.len() + 16);

// reserve_exact avoids Vec's deliberate growth heuristic, but the allocator
// may still provide more memory than requested.
v.reserve_exact(4);
assert!(v.capacity() >= v.len() + 4);
```

Use `reserve` for normal amortized-growth behavior. Reach for `reserve_exact` only when avoiding deliberate over-reservation matters enough to justify potentially more frequent reallocations.

## Estimating Capacity

```rust
#[derive(Clone, Copy)]
struct Item(i32);

fn process_item(item: &Item) -> i32 { item.0 * 2 }

fn collect_results(items: &[Item]) -> Vec<i32> {
    let mut results = Vec::with_capacity(items.len());
    for item in items {
        results.push(process_item(item));
    }
    results
}

fn filter_positive(items: &[Item]) -> Vec<&Item> {
    // This estimate is workload-specific; it is not a correctness requirement.
    let mut valid = Vec::with_capacity(items.len() / 4);
    for item in items {
        if item.0 > 0 {
            valid.push(item);
        }
    }
    valid
}
```

An underestimate may cause later growth; an overestimate may retain unused memory. Capacity tuning is therefore a performance choice, not a correctness contract unless the program separately enforces a bound.

## Iterators and `collect`

```rust
let squares: Vec<_> = (0..100).map(|x| x * x).collect();
assert_eq!(squares.len(), 100);
```

Collection implementations may use an iterator's size hints to reserve efficiently, but do not turn that implementation detail into a fixed allocation-count promise. Prefer the clear iterator expression first and manually reserve when measurement or domain knowledge justifies it.

## When to Skip Pre-allocation

- the collection usually stays tiny;
- the final size is highly uncertain and over-reservation would waste meaningful memory;
- construction is cold and simplicity matters more;
- `collect` or another API already expresses the operation clearly enough and profiling shows no problem.

## See Also

- [mem-reuse-collections](mem-reuse-collections.md) - Reuse collections with `clear()`
- [mem-smallvec](mem-smallvec.md) - Inline storage for usually-small collections
- [perf-extend-batch](perf-extend-batch.md) - Use `extend()` for batch insertions
