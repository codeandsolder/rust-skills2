# own-borrow-over-clone

> Prefer `&T` borrowing over `.clone()`

## Why It Matters

Cloning allocates new memory and copies data, while borrowing is free. Unnecessary clones can significantly impact performance, especially in hot paths or with large data structures.

## Bad

```rust
fn process(data: &String) {
    let local = data.clone();  // Unnecessary allocation!
    println!("{}", local);
}

fn count_words(text: &String) -> usize {
    let owned = text.clone();  // Why clone just to read?
    owned.split_whitespace().count()
}

// Clone in a loop - multiplied cost
fn process_all(items: &[String]) {
    for item in items {
        let copy = item.clone();  // N allocations!
        handle(&copy);
    }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
fn process(data: &str) {  // Accept &str, more flexible
    println!("{}", data);  // No allocation needed
}

fn count_words(text: &str) -> usize {
    text.split_whitespace().count()  // Just borrow
}

// Borrow in a loop - zero allocations
fn process_all(items: &[String]) {
    for item in items {
        handle(item);  // Pass reference
    }
}
```

## When Clone Is Acceptable

```rust
// 1. Need owned data for storage
struct Cache {
    data: HashMap<String, String>,
}

impl Cache {
    fn insert(&mut self, key: &str, value: &str) {
        // Clone needed - we're storing owned data
        self.data.insert(key.to_string(), value.to_string());
    }
}

// 2. Need to send across threads
fn spawn_worker(data: &Config) {
    let owned = data.clone();  // Clone needed for 'static
    std::thread::spawn(move || {
        use_config(owned);
    });
}

// 3. Copy types (no heap allocation)
let x: i32 = 42;
let y = x;  // Copy, not clone - this is fine
```

## Recent Additions (Rust 1.86+)

### Cell::update (1.88) — Avoid clone-then-set

For `Copy` types, `Cell::update` eliminates the clone-then-set pattern entirely:

```rust
use std::cell::Cell;

let counter = Cell::new(0);

// Before 1.88: clone-read, then write back
counter.set(counter.get() + 1);

// 1.88+: atomic read-modify-write with a closure
counter.update(|x| x + 1);
```

See [own-cell-update](own-cell-update.md) for details.

### Vec::pop_if (1.86) — Conditional pop

```rust
let mut v = vec![1, 2, 3, 4, 5];

// Before 1.86: pop then check
let even = v.pop().filter(|x| x % 2 == 0);

// 1.86+: pop only if predicate matches
let even = v.pop_if(|x| x % 2 == 0);
```

### slice::get_disjoint_mut (1.86) — Borrow multiple indices simultaneously

```rust
let mut v = vec![1, 2, 3, 4, 5];

// Before 1.86: split_at workaround or unsafe
let (a, b) = v.split_at_mut(2);

// 1.86+: get disjoint mutable references
let [a, b] = v.get_disjoint_mut([0, 2]) else { unreachable!() };
```

### assert_matches! / debug_assert_matches! (1.96)

```rust
// Before 1.96: manual match or third-party crate
match result {
    Ok(value) => assert_eq!(value, 42),
    _ => panic!("unexpected"),
}

// 1.96+: concise, with formatting support
assert_matches!(result, Ok(42));
```

### Edition 2024 RPIT Lifetime Capture

In Edition 2024, return-position `impl Trait` (RPIT) automatically captures all in-scope lifetimes. This means many functions that previously needed explicit lifetime annotations or clones-for-lifetime workarounds now just work:

```rust
// Edition 2021: must name lifetimes or clone
fn process(&self, items: &[u8]) -> impl Iterator<Item = &[u8]> + '_ { ... }

// Edition 2024: lifetimes are automatically captured
fn process(&self, items: &[u8]) -> impl Iterator<Item = &[u8]> { ... }
```

See [own-lifetime-elision](own-lifetime-elision.md) and [own-cow-rpit-edition2024](own-cow-rpit-edition2024.md).

## See Also

- [own-slice-over-vec](own-slice-over-vec.md) - Accept slices instead of references to collections
- [own-cow-conditional](own-cow-conditional.md) - Use Cow for conditional ownership
- [own-cell-update](own-cell-update.md) - Cell::update for Copy types
- [own-lifetime-elision](own-lifetime-elision.md) - Lifetime elision rules
- [mem-clone-from](mem-clone-from.md) - Reuse allocations when cloning
