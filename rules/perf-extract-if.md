# perf-extract-if

> Use `extract_if` when matching elements should be removed while their ownership is yielded to the caller.

**Rule**: `perf-extract-if`

## Why It Matters

`extract_if` combines conditional removal with an iterator over the removed values. That is useful when you need **both** partitions: retain non-matching values in the original collection and process/collect matching values by ownership.

Current stable Rust provides:

- `Vec::extract_if(range, pred)` since 1.87,
- `HashMap::extract_if(pred)` and `HashSet::extract_if(pred)` since 1.88,
- `BTreeMap::extract_if(range, pred)` since 1.91.

The returned iterators are lazy. If you stop consuming them early, unvisited elements remain in the original collection.

## Bad: Clone Matching Elements, Then Scan Again to Retain

<!-- rust-check: compile -->
```rust
#[derive(Clone, Debug, PartialEq, Eq)]
struct Task {
    id: u32,
    priority: u8,
}

fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    let high = tasks
        .iter()
        .filter(|task| task.priority > 5)
        .cloned()
        .collect::<Vec<_>>();

    tasks.retain(|task| task.priority <= 5);
    high
}
```

This performs separate selection/removal work and clones the extracted `Task`s. It may still be perfectly acceptable when simplicity matters more than the extra work or when cloning is cheap.

## Good: Remove and Yield Ownership in One Operation

<!-- rust-check: compile -->
```rust
#[derive(Debug, PartialEq, Eq)]
struct Task {
    id: u32,
    priority: u8,
}

fn extract_high_priority(tasks: &mut Vec<Task>) -> Vec<Task> {
    tasks
        .extract_if(.., |task| task.priority > 5)
        .collect()
}

let mut tasks = vec![
    Task { id: 1, priority: 2 },
    Task { id: 2, priority: 9 },
    Task { id: 3, priority: 4 },
];

let high = extract_high_priority(&mut tasks);
assert_eq!(high, [Task { id: 2, priority: 9 }]);
assert_eq!(tasks.len(), 2);
```

`Vec::extract_if` passes each eligible element to the predicate as `&mut T`, so the predicate may also mutate elements whether or not it removes them.

## Vec Range Extraction

`Vec::extract_if` takes a positional range. Passing `..` examines the entire vector.

<!-- rust-check: compile -->
```rust
let mut items = vec![1, 2, 3, 4, 5, 6];
let extracted = items
    .extract_if(1..4, |value| *value % 2 == 0)
    .collect::<Vec<_>>();

assert_eq!(items, [1, 3, 5, 6]);
assert_eq!(extracted, [2, 4]);
```

Only positions in the requested original range are candidates for removal.

## Hash Collections

Hash-map/set extraction has no range argument.

<!-- rust-check: compile -->
```rust
use std::collections::{HashMap, HashSet};

fn hash_examples() {
    let mut map: HashMap<&str, i32> =
        [("a", 1), ("b", 2), ("c", 3), ("d", 4)].into();
    let large: HashMap<_, _> = map.extract_if(|_, value| *value > 2).collect();
    assert_eq!(map.len(), 2);
    assert_eq!(large.len(), 2);

    let mut set: HashSet<i32> = [1, 2, 3, 4, 5, 6].into();
    let odds: HashSet<_> = set.extract_if(|value| *value % 2 == 1).collect();
    assert_eq!(set.len(), 3);
    assert_eq!(odds.len(), 3);
}
```

For `HashMap`, the predicate receives `(&K, &mut V)`; keys are not mutable because changing a key could invalidate the map's hash/equality invariants.

## BTreeMap Range Extraction

`BTreeMap::extract_if` combines a **key range** with the predicate.

<!-- rust-check: compile -->
```rust
use std::collections::BTreeMap;

fn extract_middle_evens() {
    let mut map: BTreeMap<i32, i32> = (0..10).map(|x| (x, x)).collect();

    let extracted: BTreeMap<_, _> = map
        .extract_if(2..=7, |key, _value| key % 2 == 0)
        .collect();

    assert_eq!(extracted.keys().copied().collect::<Vec<_>>(), [2, 4, 6]);
    assert!(!map.contains_key(&2));
    assert!(map.contains_key(&8));
}
```

## Consume the Iterator When You Mean “Extract All Matches”

The iterator performs work as it is advanced. If it is dropped early, unvisited elements remain.

<!-- rust-check: compile -->
```rust
fn remove_only_first_even(values: &mut Vec<i32>) -> Option<i32> {
    values.extract_if(.., |value| *value % 2 == 0).next()
}

let mut values = vec![1, 2, 4, 6];
assert_eq!(remove_only_first_even(&mut values), Some(2));
// 4 and 6 were never visited, so they remain.
assert_eq!(values, [1, 4, 6]);
```

When all matches should be removed, exhaust the iterator with `collect`, a loop, `for_each(drop)`, or another consuming operation.

## When `retain` Is Simpler

If you only need to remove values and do **not** need ownership of what was removed, `retain` / `retain_mut` usually expresses the intent more directly.

<!-- rust-check: compile -->
```rust
fn remove_zeroes(values: &mut Vec<i32>) {
    values.retain(|value| *value != 0);
}
```

Do not choose `extract_if` solely because it is newer. Choose it because yielding removed ownership is useful, or because range-limited extraction/mutation matches the operation.

## Performance Notes

`extract_if` can avoid cloning removed values and rebuilding the retained partition, but it is not a universal speedup over every hand-written alternative. Predicate cost, collection type, ordering requirements, and what you do with the removed values all matter.

Use the API for the right ownership semantics first; benchmark if the operation is actually hot.

## See Also

- [perf-drain-reuse](./perf-drain-reuse.md) - Draining and allocation reuse
- [perf-collect-into](./perf-collect-into.md) - Reusing destination collections
- [perf-entry-api](./perf-entry-api.md) - Entry-based map mutation
