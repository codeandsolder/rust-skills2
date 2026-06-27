# perf-extract-if

> Use `extract_if` for conditional extraction (Rust 1.88+)

**Rule**: `perf-extract-if`

## Why It Matters

`Vec::extract_if`, `HashMap::extract_if`, and `HashSet::extract_if` (stabilized in Rust 1.88) allow removing elements matching a predicate while moving them into an iterator. Unlike the manual `retain` + `clone` + `collect` pattern, `extract_if` does a single pass, avoids cloning, and reuses the existing allocation.

## Bad

```rust
// Manual retain + collect: two passes, clones
fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    let high: Vec<_> = tasks.iter()
        .filter(|t| t.priority > 5)
        .cloned()     // Clone because we still borrow
        .collect();
    tasks.retain(|t| t.priority <= 5);
    // Two passes, O(n) clones, extra allocation
    high
}

// Drain + filter: also two passes, intermediate allocation
fn extract_evens(numbers: &mut Vec<i32>) -> Vec<i32> {
    let all: Vec<_> = numbers.drain(..).collect();
    let evens: Vec<_> = all.into_iter().filter(|n| n % 2 == 0).collect();
    // numbers is now empty — we had to drain everything
    evens
}

// HashMap retain + collect: three lookups per entry
use std::collections::HashMap;
fn extract_large(map: &mut HashMap<String, u64>) -> HashMap<String, u64> {
    let large: HashMap<_, _> = map.iter()
        .filter(|(_, &v)| v > 100)
        .map(|(k, v)| (k.clone(), *v))
        .collect();
    map.retain(|_, &mut v| v <= 100);
    large
}
```

## Good

```rust
// Single pass, no clones, no double iteration
fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    tasks.extract_if(|t| t.priority > 5).collect()
    // tasks retains low-priority items
    // extracted Vec has high-priority items, moved not cloned
}

// extract_if on Vec
fn extract_evens(numbers: &mut Vec<i32>) -> Vec<i32> {
    numbers.extract_if(|n| *n % 2 == 0).collect()
    // numbers = [1, 3, 5, ...]
    // evens = [2, 4, 6, ...]
}

// extract_if on HashMap — single pass
fn extract_large(map: &mut HashMap<String, u64>) -> HashMap<String, u64> {
    map.extract_if(|_, &mut v| v > 100).collect()
    // Only one HashMap lookup per entry
}
```

## API Reference

| Collection | Method | Since | Returns |
|------------|--------|-------|---------|
| `Vec<T>` | `.extract_if(pred)` | 1.88 | `ExtractIf<'_, T, impl FnMut(&mut T) -> bool>` |
| `HashMap<K,V>` | `.extract_if(pred)` | 1.88 | `ExtractIf<'_, K, V, impl FnMut(&K, &mut V) -> bool>` |
| `HashSet<T>` | `.extract_if(pred)` | 1.88 | `ExtractIf<'_, T, impl FnMut(&T) -> bool>` |

## Vec Patterns

```rust
// Split into two vectors by predicate
let mut items = vec![1, 2, 3, 4, 5, 6];
let extracted: Vec<_> = items.extract_if(|n| *n % 2 == 0).collect();
// items = [1, 3, 5]
// extracted = [2, 4, 6]

// Process extracted items in place
for mut bad in items.extract_if(|i| i.is_corrupt()) {
    bad.repair();
    // items no longer contains bad
}

// Extract with index (predicate receives &mut T)
let mut indexed = vec![(0, 'a'), (1, 'b'), (2, 'c')];
let evens: Vec<_> = indexed.extract_if(|(i, _)| *i % 2 == 0).collect();
// indexed = [(1, 'b')]
```

## HashMap Patterns

```rust
use std::collections::HashMap;

let mut map: HashMap<&str, i32> = [
    ("a", 1), ("b", 2), ("c", 3), ("d", 4)
].into();

// Extract entries with values > 2
let large: HashMap<_, _> = map.extract_if(|_, v| *v > 2).collect();
// map = {"a": 1, "b": 2}
// large = {"c": 3, "d": 4}

// Extract by key predicate
let a_only: HashMap<_, _> = map.extract_if(|k, _| k.starts_with('a')).collect();
```

## HashSet Patterns

```rust
use std::collections::HashSet;

let mut set: HashSet<i32> = [1, 2, 3, 4, 5, 6].into();

// Extract odd numbers
let odds: HashSet<_> = set.extract_if(|n| *n % 2 == 1).collect();
// set = {2, 4, 6}
// odds = {1, 3, 5}
```

## Performance Comparison

| Pattern | Passes | Clones | Allocations |
|---------|--------|-------|-------------|
| `retain` + `filter` + `clone` + `collect` | 2 | Yes | O(n) |
| `drain(..)`.`filter` + `collect` | 1 | No | O(n) total |
| `extract_if(pred)`.`collect` | 1 | No | O(extracted) |

## See Also

- [perf-drain-reuse](./perf-drain-reuse.md) - drain and extract_if for reuse
- [perf-collect-into](./perf-collect-into.md) - collect_into for reuse
- [perf-entry-api](./perf-entry-api.md) - Entry API for maps
