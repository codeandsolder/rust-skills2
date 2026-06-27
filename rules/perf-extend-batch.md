# perf-extend-batch

> Use extend for batch insertions

## Why It Matters

`extend()` can pre-allocate capacity for the incoming elements and insert them in a single operation. Individual `push()` calls may trigger multiple reallocations as the collection grows. For adding multiple elements, `extend()` is both faster and clearer.

## Bad

```rust
// Multiple potential reallocations
fn collect_results(sources: Vec<Source>) -> Vec<Result> {
    let mut results = Vec::new();
    
    for source in sources {
        for result in source.get_results() {
            results.push(result);  // May reallocate
        }
    }
    results
}

// Loop with push for known data
fn build_list() -> Vec<i32> {
    let mut list = Vec::new();
    for i in 0..1000 {
        list.push(i);  // Many reallocations
    }
    list
}

// Appending another collection
fn combine(mut a: Vec<i32>, b: Vec<i32>) -> Vec<i32> {
    for item in b {
        a.push(item);
    }
    a
}
```

## Good

```rust
// Single extend with size hint
fn collect_results(sources: Vec<Source>) -> Vec<Result> {
    let mut results = Vec::new();
    
    for source in sources {
        results.extend(source.get_results());
    }
    results
}

// Direct collection from iterator
fn build_list() -> Vec<i32> {
    (0..1000).collect()
}

// Extend for combining
fn combine(mut a: Vec<i32>, b: Vec<i32>) -> Vec<i32> {
    a.extend(b);
    a
}
```

## Extend with Capacity

For best performance, combine with `reserve()`:

```rust
fn merge_all(chunks: Vec<Vec<Item>>) -> Vec<Item> {
    // Calculate total size
    let total: usize = chunks.iter().map(|c| c.len()).sum();
    
    let mut result = Vec::with_capacity(total);
    for chunk in chunks {
        result.extend(chunk);
    }
    result
}
```

## Extend Methods

| Method | Description |
|--------|-------------|
| `.extend(iter)` | Add all elements from iterator |
| `.extend_from_slice(&[T])` | Add from slice (for `Copy` types) |
| `.extend_from_within(range)` | Clone elements from within the Vec |
| `.append(&mut Vec)` | Move all from another Vec |

## extend_from_within

`Vec::extend_from_within` copies elements from within the same Vec without an external source iterator:

```rust
let mut vec = vec![1, 2, 3];
vec.extend_from_within(..);   // vec == [1, 2, 3, 1, 2, 3]
vec.extend_from_within(..2);  // vec == [1, 2, 3, 1, 2, 3, 1, 2]
```

This is more efficient than `vec.extend(vec[..].to_vec())` because it avoids an intermediate allocation. The source range can overlap with the new elements — the Vec handles it correctly.

## Pattern: Building Strings

```rust
// Bad: multiple allocations
fn build_message(parts: &[&str]) -> String {
    let mut result = String::new();
    for part in parts {
        result.push_str(part);  // May reallocate
    }
    result
}

// Good: extend with known parts
fn build_message(parts: &[&str]) -> String {
    let total_len: usize = parts.iter().map(|s| s.len()).sum();
    let mut result = String::with_capacity(total_len);
    for part in parts {
        result.push_str(part);
    }
    result
}

// Better: collect/join
fn build_message(parts: &[&str]) -> String {
    parts.concat()  // or parts.join("")
}
```

## HashMap/HashSet Extend

```rust
use std::collections::HashMap;

// Extend from iterator of tuples
fn merge_maps(mut base: HashMap<String, i32>, other: HashMap<String, i32>) -> HashMap<String, i32> {
    base.extend(other);  // Moves entries from other
    base
}

// Extend from iterator
let mut set = HashSet::new();
set.extend(items.iter().map(|i| i.id));
```

## Performance

| Operation | Allocations | Complexity |
|-----------|-------------|------------|
| N × `push()` | O(log N) | O(N) amortized |
| `extend(iter)` | O(1)* | O(N) |
| `with_capacity` + `extend` | 1 | O(N) |

*When iterator provides accurate `size_hint()`

## See Also

- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocation
- [perf-drain-reuse](./perf-drain-reuse.md) - Reusing allocations
- [perf-collect-into](./perf-collect-into.md) - collect_into for reuse
- [mem-reuse-collections](./mem-reuse-collections.md) - Collection reuse
