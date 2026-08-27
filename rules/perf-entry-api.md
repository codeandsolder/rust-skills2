# perf-entry-api

> Use entry API for map insert-or-update

## Why It Matters

The entry API performs a single lookup for insert-or-update operations. Without it, you lookup twice: once to check existence, once to insert. For `HashMap` and `BTreeMap`, the entry API is both faster and more idiomatic.

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding map and value context -->
```rust
use std::collections::HashMap;

// Double lookup: contains_key + insert
fn increment(map: &mut HashMap<String, u32>, key: String) {
    if map.contains_key(&key) {
        *map.get_mut(&key).unwrap() += 1;
    } else {
        map.insert(key, 1);
    }
}

// Double lookup with get + insert
fn get_or_insert(map: &mut HashMap<String, Vec<i32>>, key: String) -> &mut Vec<i32> {
    if !map.contains_key(&key) {
        map.insert(key.clone(), Vec::new());
    }
    map.get_mut(&key).unwrap()
}

// Triple lookup pattern
fn update_or_default(map: &mut HashMap<String, Config>, key: &str, value: i32) {
    match map.get(key) {
        Some(config) => {
            let mut new_config = config.clone();
            new_config.value = value;
            map.insert(key.to_string(), new_config);
        }
        None => {
            map.insert(key.to_string(), Config::default());
        }
    }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use std::collections::HashMap;
use std::collections::hash_map::Entry;

// Single lookup with entry
fn increment(map: &mut HashMap<String, u32>, key: String) {
    *map.entry(key).or_insert(0) += 1;
}

// Single lookup, returns mutable reference
fn get_or_insert(map: &mut HashMap<String, Vec<i32>>, key: String) -> &mut Vec<i32> {
    map.entry(key).or_insert_with(Vec::new)
}

// Single lookup with and_modify
fn update_or_default(map: &mut HashMap<String, Config>, key: String, value: i32) {
    map.entry(key)
        .and_modify(|config| config.value = value)
        .or_insert_with(Config::default);
}
```

## Entry API Methods

| Method | Behavior |
|--------|----------|
| `.or_insert(val)` | Insert `val` if empty |
| `.or_insert_with(f)` | Insert `f()` if empty (lazy) |
| `.or_default()` | Insert `Default::default()` if empty |
| `.and_modify(f)` | Apply `f` if occupied |
| `.or_insert_with_key(f)` | Insert `f(&key)` if empty |

## Anti-Pattern: or_insert_with When You Need the Key

When the value depends on the key, use `or_insert_with_key` instead of capturing the key in a closure:

```rust
// Bad: clones key into closure
map.entry(key.clone()).or_insert_with(|| compute(key));

// Good: key passed to closure
map.entry(key).or_insert_with_key(|k| compute(k));
```

## BTreeMap insert_entry (Rust 1.92+)

`BTreeMap::Entry::insert_entry(value)` inserts and returns an `OccupiedEntry`, enabling chained mutation without a second lookup:

```rust
use std::collections::BTreeMap;

let mut map = BTreeMap::new();

// Insert and get OccupiedEntry in one operation
let entry = map.entry("key").insert_entry("value");
// entry: OccupiedEntry — no second lookup needed
*entry.into_mut() = "updated";
```

This is especially useful for `BTreeMap` where lookups are O(log n):

```rust
struct Counter {
    inner: BTreeMap<String, u64>,
}

impl Counter {
    fn inc(&mut self, key: String) {
        self.inner
            .entry(key)
            .and_modify(|c| *c += 1)
            .or_insert(1);
    }

    fn inc_and_get(&mut self, key: String) -> &mut u64 {
        self.inner
            .entry(key)
            .or_insert_with_key(|k| k.len() as u64)
    }
}
```

## HashMap extract_if (Rust 1.87+)

For conditional removal of entries, `HashMap::extract_if` (stable since 1.87) avoids the double-iteration of `retain` + separate collection:

```rust
use std::collections::HashMap;

let mut map: HashMap<&str, i32> = [("a", 1), ("b", 2), ("c", 3)].into();

// Extract entries matching predicate in one pass
let small: HashMap<_, _> = map.extract_if(|_, v| *v <= 1).collect();
// map = {"b": 2, "c": 3}
// small = {"a": 1}
```

## Pattern: Count Occurrences

```rust
fn word_count(text: &str) -> HashMap<&str, usize> {
    let mut counts = HashMap::new();
    for word in text.split_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}
```

## Pattern: Group By

```rust
fn group_by_category(items: Vec<Item>) -> HashMap<Category, Vec<Item>> {
    let mut groups: HashMap<Category, Vec<Item>> = HashMap::new();
    for item in items {
        groups.entry(item.category.clone())
            .or_default()
            .push(item);
    }
    groups
}
```

## Pattern: Complex Entry Logic

```rust
match map.entry(key) {
    Entry::Occupied(mut entry) => {
        let value = entry.get_mut();
        if should_update(value) {
            *value = new_value;
        }
    }
    Entry::Vacant(entry) => {
        entry.insert(default_value);
    }
}
```

## Performance

| Pattern | Lookups | Hash Computations |
|---------|---------|-------------------|
| `contains_key` + `insert` | 2 | 2 |
| `get` + `insert` | 2 | 2 |
| `entry().or_insert()` | 1 | 1 |
| `entry().insert_entry()` | 1 | 1 |

## See Also

- [perf-extend-batch](./perf-extend-batch.md) - Batch insertions
- [perf-extract-if](./perf-extract-if.md) - Conditional extraction
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocate maps
- [perf-drain-reuse](./perf-drain-reuse.md) - Reuse map allocations
