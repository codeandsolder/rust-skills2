# perf-drain-reuse

> Use drain and extract_if to reuse allocations

## Why It Matters

`drain()` removes elements from a collection while keeping its allocated capacity. This allows reusing the same allocation across iterations, avoiding repeated allocate/deallocate cycles in loops. Since Rust 1.87, `extract_if` provides conditional drain semantics — removing only selected elements while keeping the rest — without a separate filter pass.

## Bad

```rust
// Allocates new Vec every iteration
fn process_batches(data: Vec<Item>) {
    let mut remaining = data;
    
    while !remaining.is_empty() {
        let batch: Vec<_> = remaining.drain(..100.min(remaining.len())).collect();
        process_batch(batch);
        // remaining keeps its capacity - good
        // but batch allocates new every time - bad
    }
}

// Clears and reallocates
fn reuse_buffer() {
    for _ in 0..1000 {
        let mut buffer = Vec::new();  // Allocates each iteration
        fill_buffer(&mut buffer);
        process(&buffer);
    }
}

// Manual retain + collect pattern (wasteful)
fn extract_high_priority(work: &mut Vec<Task>) {
    let high_priority: Vec<_> = work.iter()
        .filter(|t| t.priority > 5)
        .cloned()  // Clone because we still hold the borrow
        .collect();
    work.retain(|t| t.priority <= 5);
    // Two passes, clones, intermediate allocation
}
```

## Good

```rust
// Reuses allocation with drain
fn process_batches(mut data: Vec<Item>) {
    let mut batch = Vec::with_capacity(100);
    
    while !data.is_empty() {
        batch.extend(data.drain(..100.min(data.len())));
        process_batch(&batch);
        batch.clear();  // Keeps capacity
    }
}

// Reuses buffer across iterations
fn reuse_buffer() {
    let mut buffer = Vec::new();
    
    for _ in 0..1000 {
        buffer.clear();  // Keeps capacity
        fill_buffer(&mut buffer);
        process(&buffer);
    }
}

// extract_if (Rust 1.87+) — single pass, no clones
fn extract_high_priority(work: &mut Vec<Task>) -> Vec<Task> {
    work.extract_if(|t| t.priority > 5).collect()
    // work retains only low-priority tasks
    // no clones, no double iteration
}
```

## Drain Methods

| Collection | Method | Behavior |
|------------|--------|----------|
| `Vec<T>` | `.drain(range)` | Remove range, shift remaining |
| `Vec<T>` | `.drain(..)` | Remove all (like clear) |
| `VecDeque<T>` | `.drain(range)` | Remove range |
| `String` | `.drain(range)` | Remove char range |
| `HashMap<K,V>` | `.drain()` | Remove all entries |
| `HashSet<T>` | `.drain()` | Remove all elements |

## extract_if (Rust 1.87+)

`extract_if` replaces the nightly `drain_filter`. It returns an iterator that yields elements matching a predicate, removing them from the original collection. The original collection retains the non-matching elements.

| Collection | Method | Behavior |
|------------|--------|----------|
| `Vec<T>` | `.extract_if(pred)` | Extract matching elements |
| `HashMap<K,V>` | `.extract_if(pred)` | Extract matching entries |
| `HashSet<T>` | `.extract_if(pred)` | Extract matching elements |

```rust
// Vec: extract matching, keep rest
let mut numbers = vec![1, 2, 3, 4, 5, 6];
let evens: Vec<_> = numbers.extract_if(|n| *n % 2 == 0).collect();
// numbers == [1, 3, 5]
// evens == [2, 4, 6]

// HashMap: extract entries matching predicate
use std::collections::HashMap;
let mut map: HashMap<&str, i32> = [("a", 1), ("b", 2), ("c", 3)].into();
let over_one: HashMap<_, _> = map.extract_if(|_, v| *v > 1).collect();
// map contains only ("a", 1)
```

## VecDeque pop_front_if / pop_back_if (Rust 1.93+)

For dequeues, specialized conditional removal avoids scanning the entire buffer:

```rust
use std::collections::VecDeque;

let mut deque: VecDeque<i32> = (1..=10).collect();

// Remove from front while predicate holds
while let Some(val) = deque.pop_front_if(|x| *x < 5) {
    process_small(val);
}
// deque now starts at 5

// Remove from back while predicate holds
while let Some(val) = deque.pop_back_if(|x| *x > 8) {
    process_large(val);
}
// deque now ends at 8
```

## BTreeMap insert_entry (Rust 1.92+)

For `BTreeMap`, `.entry(key).insert_entry(value)` returns an `OccupiedEntry` after insertion, enabling further mutation without a second lookup:

```rust
use std::collections::BTreeMap;

let mut map = BTreeMap::new();
map.entry("key")
    .insert_entry("value")  // Insert and get OccupiedEntry
    .into_mut();            // Mutable reference to the value
```

## Pattern: Batch Processing

```rust
fn process_in_chunks(mut items: Vec<Item>, chunk_size: usize) {
    while !items.is_empty() {
        let chunk: Vec<_> = items.drain(..chunk_size.min(items.len())).collect();
        process_chunk(chunk);
    }
}
```

## Pattern: Transfer Between Collections

```rust
// Move all elements without reallocation
fn transfer_all(src: &mut Vec<Item>, dst: &mut Vec<Item>) {
    dst.extend(src.drain(..));
    // src is now empty but keeps capacity
}

// Move matching elements (classic approach)
fn transfer_matching(src: &mut Vec<Item>, dst: &mut Vec<Item>, predicate: impl Fn(&Item) -> bool) {
    let matching: Vec<_> = src.drain(..).filter(predicate).collect();
    dst.extend(matching);
}

// Move matching elements (Rust 1.87+)
fn transfer_matching_modern(src: &mut Vec<Item>, dst: &mut Vec<Item>, predicate: impl Fn(&Item) -> bool) {
    dst.extend(src.extract_if(predicate));
    // Single pass, no intermediate allocation
}
```

## Pattern: HashMap Drain

```rust
use std::collections::HashMap;

fn process_and_clear(map: &mut HashMap<String, Value>) {
    // Process all entries, clearing the map
    for (key, value) in map.drain() {
        process(key, value);
    }
    // map is now empty but keeps capacity
}
```

## drain vs clear vs take

| Operation | Elements | Capacity | Returns |
|-----------|----------|----------|---------|
| `.clear()` | Removed | Kept | Nothing |
| `.drain(..)` | Removed | Kept | Iterator |
| `.extract_if(pred)` | Some removed | Kept | Iterator (matching only) |
| `std::mem::take()` | Moved out | Reset to 0 | Owned collection |

```rust
// clear: just empty
vec.clear();

// drain: empty and iterate
for item in vec.drain(..) {
    process(item);
}

// extract_if: conditionally remove
for bad in vec.extract_if(|x| x.is_corrupt()) {
    log_error(bad);
}

// take: swap with empty, get ownership
let old_vec = std::mem::take(&mut vec);
```

## See Also

- [perf-extract-if](./perf-extract-if.md) - extract_if details
- [mem-reuse-collections](./mem-reuse-collections.md) - Reusing collections
- [perf-extend-batch](./perf-extend-batch.md) - Batch insertions
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocation
