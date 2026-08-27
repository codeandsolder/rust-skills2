# perf-extract-if

> Use `extract_if` for conditional extraction when you need to keep both removed and retained elements

**Rule**: `perf-extract-if`

## Why It Matters

`Vec::extract_if` (Rust 1.87), `HashMap::extract_if` and `HashSet::extract_if` (Rust 1.88), and `BTreeMap::extract_if` (Rust 1.91) remove matching elements while yielding ownership of the removed values. This can replace patterns that first clone matching elements and then retain the rest.

The APIs are not identical: **`Vec::extract_if` and `BTreeMap::extract_if` take a range as their first argument**, while `HashMap` and `HashSet` do not.

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding task collection context -->
```rust
// Manual retain + collect: two passes and clones.
fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    let high: Vec<_> = tasks.iter()
        .filter(|t| t.priority > 5)
        .cloned()
        .collect();
    tasks.retain(|t| t.priority <= 5);
    high
}

// Draining everything destroys the retained partition unless it is rebuilt.
fn extract_evens(numbers: &mut Vec<i32>) -> Vec<i32> {
    let all: Vec<_> = numbers.drain(..).collect();
    all.into_iter().filter(|n| n % 2 == 0).collect()
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: domain Task type and helper context -->
```rust
use std::collections::HashMap;

fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    tasks.extract_if(.., |t| t.priority > 5).collect()
}

fn extract_evens(numbers: &mut Vec<i32>) -> Vec<i32> {
    numbers.extract_if(.., |n| *n % 2 == 0).collect()
}

fn extract_large(map: &mut HashMap<String, u64>) -> HashMap<String, u64> {
    map.extract_if(|_, v| *v > 100).collect()
}
```

Passing `..` to `Vec::extract_if` means “consider the entire vector.” A narrower range can limit which positions are eligible for extraction.

## API Reference

| Collection | Method shape | Since |
|------------|--------------|-------|
| `Vec<T>` | `.extract_if(range, pred)` | 1.87 |
| `HashMap<K, V>` | `.extract_if(pred)` | 1.88 |
| `HashSet<T>` | `.extract_if(pred)` | 1.88 |
| `BTreeMap<K, V>` | `.extract_if(range, pred)` | 1.91 |

## Vec Patterns

```rust
let mut items = vec![1, 2, 3, 4, 5, 6];
let extracted: Vec<_> = items.extract_if(.., |n| *n % 2 == 0).collect();
assert_eq!(items, [1, 3, 5]);
assert_eq!(extracted, [2, 4, 6]);

// Only positions 1..4 are considered.
let mut items = vec![1, 2, 3, 4, 5, 6];
let extracted: Vec<_> = items.extract_if(1..4, |n| *n % 2 == 0).collect();
assert_eq!(items, [1, 3, 5, 6]);
assert_eq!(extracted, [2, 4]);
```

## HashMap and HashSet Patterns

```rust
use std::collections::{HashMap, HashSet};

let mut map: HashMap<&str, i32> = [
    ("a", 1), ("b", 2), ("c", 3), ("d", 4)
].into();
let large: HashMap<_, _> = map.extract_if(|_, v| *v > 2).collect();
assert_eq!(map.len(), 2);
assert_eq!(large.len(), 2);

let mut set: HashSet<i32> = [1, 2, 3, 4, 5, 6].into();
let odds: HashSet<_> = set.extract_if(|n| *n % 2 == 1).collect();
assert_eq!(set.len(), 3);
assert_eq!(odds.len(), 3);
```

## BTreeMap Range Extraction

```rust
use std::collections::BTreeMap;

let mut map: BTreeMap<i32, i32> = (0..8).map(|x| (x, x)).collect();
let evens: BTreeMap<_, _> = map
    .extract_if(.., |k, _| k % 2 == 0)
    .collect();
assert_eq!(evens.len(), 4);
assert_eq!(map.len(), 4);
```

Because `BTreeMap::extract_if` takes a key range, it can also extract conditionally from only part of the ordered map.

## Performance Notes

`extract_if` is useful when the removed values are needed and retaining the original allocation matters. It avoids cloning elements merely to create the removed partition. Do not assume it is universally faster than `retain`: if you do not need ownership of removed elements, `retain`/`retain_mut` is usually the simpler operation.

If an `extract_if` iterator is dropped before it is exhausted, unvisited elements remain in the collection. Consume the iterator when the intent is to process the whole requested range.

## See Also

- [perf-drain-reuse](./perf-drain-reuse.md) - drain and extraction patterns
- [perf-collect-into](./perf-collect-into.md) - collection reuse
- [perf-entry-api](./perf-entry-api.md) - Entry API for maps
