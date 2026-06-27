# perf-collect-into

> Use `extend()` for reusing containers; `collect_into` (nightly) for future ergonomics

## Why It Matters

Every `.collect()` allocates a new collection. In loops, repeatedly creating new collections wastes memory and CPU. The stable pattern is `clear() + extend()` — it reuses the allocation without reallocating. A proposed `collect_into()` method (`#![feature(iter_collect_into)]`, nightly-only) would make this pattern more ergonomic by combining clear and extend into a single call.

## Bad

```rust
// Allocates new Vec each time
fn process_batches(batches: Vec<Vec<i32>>) -> Vec<Vec<i32>> {
    batches.into_iter()
        .map(|batch| {
            batch.into_iter()
                .filter(|x| *x > 0)
                .collect::<Vec<_>>()  // New allocation per batch
        })
        .collect()
}

// Can't reuse cleared buffer
fn filter_loop(data: &[Vec<i32>]) {
    for batch in data {
        let filtered: Vec<_> = batch.iter()
            .filter(|&&x| x > 0)
            .copied()
            .collect();  // New allocation each iteration
        process(&filtered);
    }
}
```

## Good

```rust
// Reuse buffer with clear + extend (stable, Rust 1.0+)
fn filter_loop(data: &[Vec<i32>]) {
    let mut buffer = Vec::new();
    
    for batch in data {
        buffer.clear();  // Keeps allocation
        buffer.extend(
            batch.iter()
                .filter(|&&x| x > 0)
                .copied()
        );
        process(&buffer);
    }
}

// Nightly only: collect_into (requires #![feature(iter_collect_into)])
// Combines clear + extend in one call; not available on stable Rust.
#![cfg_attr(nightly, feature(iter_collect_into))]
fn filter_loop_nightly(data: &[Vec<i32>]) {
    let mut buffer = Vec::new();
    
    for batch in data {
        buffer.clear();
        batch.iter()
            .filter(|&&x| x > 0)
            .copied()
            .collect_into(&mut buffer);
        process(&buffer);
    }
}
```

## Complementary: extract_if for Conditional Collection

Combine `clear()` + `extend()` with `Vec::extract_if` (Rust 1.87+) for efficient conditional collection without double iteration:

```rust
let mut items: Vec<Item> = get_items();
let mut extracted = Vec::with_capacity(items.len());
let mut kept = Vec::with_capacity(items.len());

// Drain-splice: extract matching items, keep non-matching
for mut item in items.extract_if(|i| i.should_extract()) {
    item.transform();
    extracted.push(item);
}

// items now contains only non-extracted items
// extract_if and drain did the move without cloning
```

## Vec push_mut and insert_mut (Rust 1.95+)

Since Rust 1.95, `Vec::push_mut` and `Vec::insert_mut` insert an element and return `&mut T` to the newly inserted element in one operation:

```rust
let mut vec = Vec::new();
let val = vec.push_mut(item);    // Insert and get &mut T
let val = vec.insert_mut(0, item); // Insert at index and get &mut T
```

This avoids the boilerplate of `.push()` followed by `.last_mut().unwrap()`. These methods are marked `#[must_use]` to encourage intentional use of the returned reference.

## Pattern: Transform and Reuse

```rust
fn transform_batches(batches: &[Vec<RawData>]) -> Vec<ProcessedData> {
    let mut temp = Vec::new();
    let mut all_results = Vec::new();
    
    for batch in batches {
        temp.clear();
        temp.extend(batch.iter().map(ProcessedData::from));
        
        // Process temp, append to results
        all_results.extend(temp.drain(..).filter(|p| p.is_valid()));
    }
    
    all_results
}
```

## Supported Collections

`extend()` works with any type implementing `Extend`:

```rust
use std::collections::{HashSet, HashMap, VecDeque};

let mut vec = Vec::new();
let mut set = HashSet::new();
let mut deque = VecDeque::new();

vec.extend(0..10);
set.extend(0..10);
deque.extend(0..10);
```

## Comparison

| Method | Allocation | Buffer Reuse | Stability |
|--------|------------|--------------|-----------|
| `.collect()` | New each time | No | Stable |
| `buf.extend(iter)` | Reuses buffer | Yes | Stable (1.0+) |
| `.collect_into(&mut buf)` | Reuses buffer | Yes | Nightly only |

## See Also

- [perf-drain-reuse](./perf-drain-reuse.md) - Drain for reuse
- [perf-extract-if](./perf-extract-if.md) - Conditional extraction
- [mem-reuse-collections](./mem-reuse-collections.md) - Collection reuse
- [perf-extend-batch](./perf-extend-batch.md) - Batch extensions
