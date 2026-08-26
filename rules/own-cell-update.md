# own-cell-update

**Rule**: `own-cell-update`

> Use `Cell::update` (Rust 1.88+) for concise single-threaded read-transform-write updates on `Copy` values

## Why It Matters

`Cell::update` expresses the common `get` → transform → `set` pattern directly. It is concise and keeps the transformation in one place.

It is **not an atomic operation** in the concurrency sense. `Cell<T>` provides single-threaded interior mutability and is `!Sync`; use atomic types or synchronization primitives when multiple threads can access the value.

## Bad

```rust
use std::cell::Cell;

let counter = Cell::new(0u32);
let old = counter.get();
counter.set(old + 1);
```

This is valid, but verbose when all you want is a local transformation.

## Good

```rust
use std::cell::Cell;

let counter = Cell::new(0u32);
counter.update(|x| x + 1);

let flag = Cell::new(false);
flag.update(|x| !x);
```

## Not a Replacement for Atomics

```rust
use std::sync::atomic::{AtomicUsize, Ordering};

static REQUESTS: AtomicUsize = AtomicUsize::new(0);

fn count_request() {
    REQUESTS.fetch_add(1, Ordering::Relaxed);
}
```

Use `Atomic*`, `Mutex`, or another synchronization primitive when cross-thread synchronization is required.

## Key Points

- `Cell::update` is a convenience API for single-threaded interior mutation.
- Do not describe it as atomic or synchronizing.
- `Cell` is best for `Copy` values behind shared references in single-threaded code.
- For non-`Copy` interior mutation, consider `RefCell`; for cross-thread mutation, use synchronization designed for that purpose.

## See Also

- [own-refcell-interior](./own-refcell-interior.md) — dynamic borrow checking for non-`Copy` values
- [own-mutex-interior](./own-mutex-interior.md) — thread-safe interior mutability
- [`Cell::update`](https://doc.rust-lang.org/stable/std/cell/struct.Cell.html#method.update)
