# perf-entry-api

> Use a map's entry API when one key lookup should decide both the occupied and vacant cases.

## Why It Matters

`HashMap::entry` and `BTreeMap::entry` expose a view of one key position as either occupied or vacant. This is ideal for insert-or-update logic because the lookup/navigation used to find that entry can be reused instead of spelling separate `contains_key`/`get_mut`/`insert` operations.

That often improves both clarity and work performed, but do not reduce the rule to “entry is always faster.” An entry API typically takes ownership of a key, while borrowed lookup methods can avoid constructing/owning a key when the occupied case dominates. Choose the API that matches the ownership and mutation pattern.

## Bad: Search, Then Search Again

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn increment(map: &mut HashMap<String, u32>, key: String) {
    if map.contains_key(&key) {
        *map.get_mut(&key).unwrap() += 1;
    } else {
        map.insert(key, 1);
    }
}

fn get_or_insert(
    map: &mut HashMap<String, Vec<i32>>,
    key: String,
) -> &mut Vec<i32> {
    if !map.contains_key(&key) {
        map.insert(key.clone(), Vec::new());
    }
    map.get_mut(&key).unwrap()
}
```

These are valid, but the control flow performs separate map operations for one logical key decision and the second example also clones the key.

## Good: Work Through One Entry

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

#[derive(Default)]
struct Config {
    value: i32,
}

fn increment(map: &mut HashMap<String, u32>, key: String) {
    *map.entry(key).or_insert(0) += 1;
}

fn get_or_insert(
    map: &mut HashMap<String, Vec<i32>>,
    key: String,
) -> &mut Vec<i32> {
    map.entry(key).or_default()
}

fn update_or_default(
    map: &mut HashMap<String, Config>,
    key: String,
    value: i32,
) {
    map.entry(key)
        .and_modify(|config| config.value = value)
        .or_insert_with(|| Config { value });
}
```

The entry object represents the result of locating that owned key and lets the occupied/vacant operations continue from it.

## Useful Entry Combinators

| Method | Behavior |
|---|---|
| `or_insert(value)` | insert eager value if vacant; return `&mut V` |
| `or_insert_with(f)` | lazily construct value if vacant |
| `or_insert_with_key(f)` | lazily construct from a reference to the moved key |
| `or_default()` | insert `V::default()` if vacant |
| `and_modify(f)` | mutate occupied value, then continue with the entry |
| `insert_entry(value)` | set a value and return an occupied-entry handle |

Use `or_insert_with` when construction is meaningfully expensive or has side effects; `or_insert` is simpler for a cheap already-available value.

## `or_insert_with_key` Avoids Recovering or Cloning the Moved Key

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn lengths(keys: impl IntoIterator<Item = String>) -> HashMap<String, usize> {
    let mut map = HashMap::new();

    for key in keys {
        map.entry(key)
            .or_insert_with_key(|stored_key| stored_key.len());
    }

    map
}
```

The closure receives `&K` for the key already moved into `entry`, so key-derived defaults do not require a second owned copy.

## Full `Entry` Matching for Asymmetric Logic

<!-- rust-check: compile -->
```rust
use std::collections::hash_map::Entry;
use std::collections::HashMap;

fn update_if_even(map: &mut HashMap<String, i32>, key: String, new_value: i32) {
    match map.entry(key) {
        Entry::Occupied(mut entry) => {
            if *entry.get() % 2 == 0 {
                entry.insert(new_value);
            }
        }
        Entry::Vacant(entry) => {
            entry.insert(new_value);
        }
    }
}
```

Use explicit `Occupied`/`Vacant` matching when combinators make the state transition harder to read.

## Entry Is Not Automatically Best for Borrowed-Lookup Fast Paths

Suppose callers hold `&str` while the map owns `String`. A borrowed `get_mut(&str)` can check the common occupied path without first allocating a new `String`. If insertion is rare, constructing an owned key only in the miss branch may beat eagerly building one for `entry`.

The useful optimization principle is **avoid redundant lookup/work**, not “always use `entry`.” Benchmark when key construction, hashing/comparison cost, or hit rate matters.

## `insert_entry`

On current Rust, hash-map entries can set a value and keep an `OccupiedEntry` handle:

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn replace_and_increment(map: &mut HashMap<&'static str, u32>) -> u32 {
    let mut entry = map.entry("jobs").insert_entry(40);
    *entry.get_mut() += 2;
    *entry.get()
}
```

This is useful when work immediately after insertion needs occupied-entry operations without another lookup.

## Conditional Extraction Is a Separate API

When the operation is “remove matching entries and keep ownership of what was removed,” use `extract_if`, not the entry API.

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

fn split_small(
    map: &mut HashMap<&'static str, i32>,
) -> HashMap<&'static str, i32> {
    map.extract_if(|_, value| *value <= 1).collect()
}
```

`HashMap::extract_if` is stable since Rust 1.88.

## See Also

- [perf-extract-if](./perf-extract-if.md) - Conditional removal with ownership
- [perf-extend-batch](./perf-extend-batch.md) - Batch insertion
- [mem-with-capacity](./mem-with-capacity.md) - Capacity planning
