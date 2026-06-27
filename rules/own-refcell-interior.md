# own-refcell-interior

> Use `RefCell<T>` for interior mutability in single-threaded code

## Why It Matters

Rust's borrow checker enforces rules at compile time, but sometimes you need to mutate data through a shared reference. `RefCell<T>` moves borrow checking to runtime, allowing mutation through `&self`. This is essential for patterns like caches, lazy initialization, and observer patterns where compile-time borrowing is too restrictive.

## Bad

```rust
struct Cache {
    // Requires &mut self to update, breaking shared reference patterns
    data: HashMap<String, String>,
}

impl Cache {
    fn get_or_compute(&mut self, key: &str) -> &str {
        // Caller needs &mut Cache, can't share cache reference
        if !self.data.contains_key(key) {
            self.data.insert(key.to_string(), expensive_compute(key));
        }
        &self.data[key]
    }
}
```

This forces exclusive access even for logically shared operations.

## Good

```rust
use std::cell::RefCell;
use std::collections::HashMap;

struct Cache {
    data: RefCell<HashMap<String, String>>,
}

impl Cache {
    fn get_or_compute(&self, key: &str) -> String {
        // Can mutate through &self
        let mut data = self.data.borrow_mut();
        if !data.contains_key(key) {
            data.insert(key.to_string(), expensive_compute(key));
        }
        data[key].clone()
    }
}

// Multiple references can coexist
let cache = Cache::new();
let ref1 = &cache;
let ref2 = &cache;
ref1.get_or_compute("key1");
ref2.get_or_compute("key2");
```

## Common Pattern: Rc<RefCell<T>>

```rust
use std::rc::Rc;
use std::cell::RefCell;

// Shared mutable state in single-threaded code
type SharedState = Rc<RefCell<AppState>>;

fn create_handlers(state: SharedState) -> Vec<Box<dyn Fn()>> {
    vec![
        Box::new({
            let state = state.clone();
            move || state.borrow_mut().increment()
        }),
        Box::new({
            let state = state.clone();
            move || state.borrow_mut().decrement()
        }),
    ]
}
```

## Runtime Panics

`RefCell` panics if you violate borrowing rules at runtime:

```rust
let cell = RefCell::new(5);
let borrow1 = cell.borrow();
let borrow2 = cell.borrow_mut(); // PANIC: already borrowed
```

Use `try_borrow()` and `try_borrow_mut()` for fallible borrowing.

## Cell::update (1.88) — Atomic Update for Copy Types

For `Copy` types, `Cell::update` provides a concise read-modify-write without separate `get`/`set` calls:

```rust
use std::cell::Cell;

let counter = Cell::new(0);

// Bad: separate read, compute, write
counter.set(counter.get() + 1);

// Good: single closure-based update
counter.update(|x| x + 1);

// With stateful computation
counter.update(|x| {
    if x > 100 { 0 } else { x + 1 }
});
```

This is especially useful when `Cell` is used for interior mutability within a `RefCell`-like pattern but the data is `Copy`.

## Cell::as_array_of_cells (1.91) — Reinterpret Array as Cell Array

```rust
use std::cell::Cell;

// 1.91+: reinterpret &Cell<[T; N]> as &[Cell<T>; N]
let cell = Cell::new([1u32, 2, 3, 4]);
let cells: &[Cell<u32>; 4] = cell.as_array_of_cells();

// Now you can mutate individual elements
cells[0].set(10);
cells[2].set(30);
// Previously required unsafe or full-array replacement
```

Combined with `Rc<Cell<[T; N]>>` for shared mutable arrays:

```rust
use std::cell::Cell;
use std::rc::Rc;

let data: Rc<Cell<[u32; 4]>> = Rc::new(Cell::new([1, 2, 3, 4]));
let cells: &[Cell<u32>; 4] = data.as_array_of_cells();
cells[1].set(42);  // Mutate element through Rc + Cell
```

## Edition 2024: RefCell Borrows and Temporary Scopes

### `if let` Temporary Scope Change

In Edition 2021, temporary borrows from `RefCell` in `if let` conditions lived until the end of the statement — causing panics:

```rust
// Edition 2021: PANICS at runtime
let cache = RefCell::new(Some("hello".to_string()));
if let Some(ref value) = *cache.borrow() {
    // Borrow is still active here...
    cache.borrow_mut();          // PANIC: already borrowed
    // ...even though value is a reference into the Ref
}
```

In **Edition 2024**, the temporary scope ends at the `if let` branch boundary, so the borrow is released before the branch body:

```rust
// Edition 2024: ✅ compiles and runs without panic
let cache = RefCell::new(Some("hello".to_string()));
if let Some(ref value) = *cache.borrow() {
    // Borrow from temporary is released at branch boundary
    cache.borrow_mut();          // ✅ OK in Edition 2024
}
```

### Tail Expression Temporary Scope

In Edition 2021, using `RefCell` borrows in tail expressions was limited:

```rust
fn len(c: RefCell<String>) -> usize {
    c.borrow().len()  // ERROR in 2021: temporary dropped while borrowed
}
```

In **Edition 2024**, the temporary scope is extended to cover the caller's use of the return value, so this compiles:

```rust
fn len(c: RefCell<String>) -> usize {
    c.borrow().len()  // ✅ OK in Edition 2024 — temporary lives long enough
}
```

These changes significantly reduce the need for workarounds like `.clone()` or explicit block-scoping when working with `RefCell`.

## See Also

- [own-cell-update](./own-cell-update.md) - Cell::update for Copy types
- [own-rc-single-thread](./own-rc-single-thread.md) - Combining with Rc for shared ownership
- [own-mutex-interior](./own-mutex-interior.md) - Thread-safe alternative
- [own-lifetime-elision](./own-lifetime-elision.md) - Edition 2024 lifetime capture
