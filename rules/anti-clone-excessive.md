# anti-clone-excessive

> Don't clone when borrowing works

## Why It Matters

`.clone()` allocates memory and copies data. When you only need to read data, borrowing (`&T`) is free. Excessive cloning wastes memory, CPU cycles, and often indicates misunderstanding of ownership.

## Bad

```rust
// Cloning to pass to a function that only reads
fn print_name(name: String) {  // Takes ownership
    println!("{}", name);
}
let name = "Alice".to_string();
print_name(name.clone());  // Unnecessary clone
print_name(name);          // Could have just done this

// Cloning in a loop
for item in items.clone() {  // Clones entire Vec
    process(&item);
}

// Cloning for comparison
if input.clone() == expected {  // Pointless clone
    // ...
}

// Cloning struct fields
fn get_name(&self) -> String {
    self.name.clone()  // Caller might not need ownership
}
```

## Good

<!-- rust-check: fragment; reason=extraction artifact: wrapper/context -->
```rust
// Accept reference if only reading
fn print_name(name: &str) {
    println!("{}", name);
}
let name = "Alice".to_string();
print_name(&name);  // Borrow, no clone

// Iterate by reference
for item in &items {
    process(item);
}

// Compare by reference
if input == expected {
    // ...
}

// Return reference when possible
fn get_name(&self) -> &str {
    &self.name
}
```

## Counter-Pattern: Premature Clone Avoidance

Avoiding `.clone()` at all costs can lead to convoluted lifetime gymnastics and overly complex code. **Clone first, optimize later.** Only refactor clones away when profiling shows they're a bottleneck.

```rust
// BAD: Over-engineered to avoid one clone
fn process<'a>(data: &'a Data, cache: &'a mut Cache) -> impl 'a + Future<Output = ()> {
    async move {
        // Complex lifetime dance to avoid cloning `data`
        let result = fetch(&data).await;
        cache.store(result).await;
    }
}

// GOOD: Clone and move — simple, readable, maintainable
fn process(data: Data, cache: Cache) -> impl Future<Output = ()> {
    async move {
        let result = fetch(&data).await;
        cache.store(result).await;
    }
}
```

## When to Clone

```rust
// Need owned data for async move
let name = name.clone();
tokio::spawn(async move {
    process(name).await;
});

// Storing in a new struct
struct Cache {
    data: String,
}
impl Cache {
    fn store(&mut self, data: &str) {
        self.data = data.to_string();  // Must own
    }
}

// Multiple owners (use Arc instead if frequent)
let shared = data.clone();
thread::spawn(move || use_data(shared));
```

## Alternatives to Clone

| Instead of | Use |
|------------|-----|
| `s.clone()` for reading | `&s` |
| `vec.clone()` for iteration | `&vec` or `vec.iter()` |
| `Clone` for shared ownership | `Arc<T>` |
| Clone in hot loop | Move outside loop |
| `s.to_string()` from `&str` | Accept `&str` if possible |
| `a.clone()` then mutate | `clone_from(&a)` to reuse allocation |

## Pattern: Clone on Write

```rust
use std::borrow::Cow;

fn process(input: Cow<str>) -> Cow<str> {
    if needs_modification(&input) {
        Cow::Owned(modify(&input))  // Clone only if needed
    } else {
        input  // No clone
    }
}
```

## Pattern: clone_from() to Reuse Allocation

When you need to update an owned value from a reference, prefer `clone_from()` — it reuses the existing allocation instead of dropping and allocating anew:

```rust
// BAD: allocates new String, drops old
self.name = other.name.clone();

// GOOD: reuses existing buffer if capacity is sufficient
self.name.clone_from(&other.name);
```

This works for `String`, `Vec`, `HashMap`, and any type implementing `Clone`.

## Detecting Excessive Clones

```toml
# Cargo.toml
[lints.clippy]
clone_on_copy = "warn"
clone_on_ref_ptr = "warn"
redundant_clone = "warn"
assigning_clones = "allow"  # pedantic, suggests clone_from()
```

## See Also

- [own-borrow-over-clone](./own-borrow-over-clone.md) - Borrowing patterns
- [own-cow-conditional](./own-cow-conditional.md) - Clone on write
- [own-arc-shared](./own-arc-shared.md) - Shared ownership
