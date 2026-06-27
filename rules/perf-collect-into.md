# perf-collect-into

> Use collect_into for reusing containers

## Why It Matters

`collect_into()` (stabilized in Rust 1.83) allows collecting iterator results into an existing collection, reusing its allocation. This avoids the allocation that `collect()` would make for a new collection.

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
// Reuse buffer with collect_into
fn filter_loop(data: &[Vec<i32>]) {
    let mut buffer = Vec::new();
    
    for batch in data {
        buffer.clear();  // Keep allocation
        batch.iter()
            .filter(|&&x| x > 0)
            .copied()
            .collect_into(&mut buffer);
        process(&buffer);
    }
}

// Also works with extend pattern
fn filter_loop_extend(data: &[Vec<i32>]) {
    let mut buffer = Vec::new();
    
    for batch in data {
        buffer.clear();
        buffer.extend(
            batch.iter()
                .filter(|&&x| x > 0)
                .copied()
        );
        process(&buffer);
    }
}
```

## Complementary: extract_if for Conditional Collection

Combine `collect_into()` with `Vec::extract_if` (Rust 1.88+) for efficient conditional collection without double iteration:

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

Since Rust 1.95, `Vec::push_mut` and `Vec::insert_mut` provide extension-like semantics for single elements with controlled capacity checks:

```rust
let mut vec = Vec::with_capacity(5);
vec.push_mut(item);   // Like push but returns Result if no capacity
vec.insert_mut(0, item); // Like insert but returns Result if no capacity
```

These are useful in constrained environments where you want explicit capacity management without the allocation that `reserve` might trigger.

## Pre-1.83 Alternative: extend

Before `collect_into()` was stabilized, use `extend()`:

```rust
fn reuse_buffer(data: &[Vec<i32>]) {
    let mut buffer = Vec::new();
    
    for batch in data {
        buffer.clear();
        buffer.extend(batch.iter().filter(|&&x| x > 0).copied());
        process(&buffer);
    }
}
```

## Pattern: Transform and Reuse

```rust
fn transform_batches(batches: &[Vec<RawData>]) -> Vec<ProcessedData> {
    let mut temp = Vec::new();
    let mut all_results = Vec::new();
    
    for batch in batches {
        temp.clear();
        batch.iter()
            .map(ProcessedData::from)
            .collect_into(&mut temp);
        
        // Process temp, append to results
        all_results.extend(temp.drain(..).filter(|p| p.is_valid()));
    }
    
    all_results
}
```

## Supported Collections

`collect_into()` works with any type implementing `Extend`:

```rust
use std::collections::{HashSet, HashMap, VecDeque};

let mut vec = Vec::new();
let mut set = HashSet::new();
let mut deque = VecDeque::new();

(0..10).collect_into(&mut vec);
(0..10).collect_into(&mut set);
(0..10).collect_into(&mut deque);
```

## Comparison

| Method | Allocation | Buffer Reuse |
|--------|------------|--------------|
| `.collect()` | New each time | No |
| `.collect_into(&mut buf)` | Reuses buffer | Yes |
| `buf.extend(iter)` | Reuses buffer | Yes |

## See Also

- [perf-drain-reuse](./perf-drain-reuse.md) - Drain for reuse
- [perf-extract-if](./perf-extract-if.md) - Conditional extraction
- [mem-reuse-collections](./mem-reuse-collections.md) - Collection reuse
- [perf-extend-batch](./perf-extend-batch.md) - Batch extensions
