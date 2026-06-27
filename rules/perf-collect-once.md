# perf-collect-once

> Don't collect intermediate iterators

## Why It Matters

Each `.collect()` allocates a new collection. Chaining multiple operations with intermediate collections wastes memory and CPU cycles. Keep iterator chains lazy and collect only once at the end.

## Bad

```rust
// Three allocations, three passes
fn process_users(users: Vec<User>) -> Vec<String> {
    let active: Vec<_> = users.into_iter()
        .filter(|u| u.is_active)
        .collect();
    
    let verified: Vec<_> = active.into_iter()
        .filter(|u| u.is_verified)
        .collect();
    
    verified.into_iter()
        .map(|u| u.name)
        .collect()
}

// Collecting to count
fn count_valid(items: &[Item]) -> usize {
    items.iter()
        .filter(|i| i.is_valid())
        .collect::<Vec<_>>()  // Unnecessary!
        .len()
}
```

## Good

```rust
// One allocation, one pass
fn process_users(users: Vec<User>) -> Vec<String> {
    users.into_iter()
        .filter(|u| u.is_active)
        .filter(|u| u.is_verified)
        .map(|u| u.name)
        .collect()
}

// No allocation needed
fn count_valid(items: &[Item]) -> usize {
    items.iter()
        .filter(|i| i.is_valid())
        .count()
}
```

## Pattern: Deferred Collection

```rust
// Create the iterator chain
fn prepare_data(raw: Vec<RawData>) -> impl Iterator<Item = ProcessedData> {
    raw.into_iter()
        .filter(|d| d.is_valid())
        .map(ProcessedData::from)
}

// Collect only when needed
let data: Vec<_> = prepare_data(input).collect();

// Or consume without collecting
prepare_data(input).for_each(|d| process(d));
```

## When Intermediate Collection Is Needed

```rust
// Need to iterate multiple times
let items: Vec<_> = data.iter()
    .filter(|x| x.is_valid())
    .collect();

let count = items.len();
let first = items.first();
for item in &items {
    process(item);
}

// Need to sort (requires concrete collection)
let mut sorted: Vec<_> = data.iter()
    .filter(|x| x.is_active)
    .collect();
sorted.sort_by_key(|x| x.priority);
```

## Comparison

| Approach | Allocations | Passes | Memory |
|----------|-------------|--------|--------|
| Multiple `.collect()` | N | N | O(N × data) |
| Single chain + `.collect()` | 1 | 1 | O(data) |
| No `.collect()` (streaming) | 0 | 1 | O(1) |

## Anti-Pattern: HashMap::values().collect() Then Iterate

Collecting `HashMap` values into a `Vec` just to iterate them wastes an allocation and a pass:

```rust
// Bad: allocate Vec then iterate
fn process_all(map: &HashMap<Key, Value>) {
    let values: Vec<_> = map.values().collect();  // Allocation!
    for v in &values {
        process(v);
    }
}

// Good: iterate directly
fn process_all(map: &HashMap<Key, Value>) {
    for v in map.values() {
        process(v);
    }
}
```

## Fixed-Size Chunk Patterns

When processing slices in fixed-size chunks, avoid intermediate collections with `<[T]>::as_chunks` (Rust 1.88+) and `<[T]>::array_windows` (Rust 1.94+):

```rust
// Bad: collect then iterate chunks
let chunks: Vec<_> = data.chunks(4).collect();
for chunk in &chunks {
    process_four(chunk[0], chunk[1], chunk[2], chunk[3]);
}

// Good: zero-allocation fixed-size chunks
let (chunks, remainder) = data.as_chunks::<4>();
for &[a, b, c, d] in chunks {
    process_four(a, b, c, d);
}
// remainder is &[T] for the leftover elements

// For sliding windows:
for &[a, b, c] in data.array_windows::<3>() {
    process_three(a, b, c);
}
```

## Pattern: Collect with Capacity

When you must collect, pre-allocate:

```rust
// With estimated capacity
let mut result = Vec::with_capacity(items.len());
result.extend(
    items.iter()
        .filter(|x| x.is_valid())
        .map(|x| x.clone())
);
```

## See Also

- [perf-iter-lazy](./perf-iter-lazy.md) - Keep iterators lazy
- [perf-array-windows](./perf-array-windows.md) - Fixed-size windows
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocate collections
- [anti-collect-intermediate](./anti-collect-intermediate.md) - Anti-pattern
