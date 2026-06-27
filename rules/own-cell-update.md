# own-cell-update

**Rule**: `own-cell-update`

> Use `Cell::update` (Rust 1.88+) for atomic read-modify-write on `Copy`-type interior-mutable data

## Why It Matters

`Cell::update` replaces the clumsy `cell.set(cell.get() + 1)` pattern with a single closure-based call. It is more concise, eliminates the risk of stale reads in single-threaded code, and removes the temptation to clone-then-set.

## Bad

```rust
use std::cell::Cell;

let counter = Cell::new(0);

// Read, compute, write — three separate operations
counter.set(counter.get() + 1);

// With more complex logic, the gap between get and set grows
counter.set(
    if counter.get() > 100 { 0 } else { counter.get() + 1 }
);
```

## Good

```rust
use std::cell::Cell;

let counter = Cell::new(0);

// Single closure — concise and atomic-for-Copy
counter.update(|x| x + 1);

// Complex logic inside the closure
counter.update(|x| if x > 100 { 0 } else { x + 1 });

// Works with any Copy type: bool, f64, enums, arrays
let flag = Cell::new(false);
flag.update(|x| !x);

let value = Cell::new(42u64);
value.update(|x| x.wrapping_mul(2));
```

## Comparison with Other Patterns

| Pattern | Lines | Readability | Safe for Copy? |
|---------|-------|-------------|----------------|
| `cell.set(cell.get() + 1)` | 1 | Medium | Yes |
| `let x = cell.get(); cell.set(x + 1)` | 2 | Medium | Yes |
| `let mut x = cell.get(); x += 1; cell.set(x)` | 3 | Low | Yes |
| `cell.update(\|x\| x + 1)` | 1 | High | Yes |

## Cross-Reference: RefCell and Mutex

`Cell::update` is the `Copy`-type equivalent of:

- **`RefCell`**: borrow mutably, mutate, drop borrow
- **`Mutex`**: lock, mutate, unlock

For non-`Copy` types or multi-threaded scenarios, use `RefCell::borrow_mut` or `Mutex::lock` instead.

See [own-refcell-interior](own-refcell-interior.md) for `RefCell` patterns and [own-mutex-interior](own-mutex-interior.md) for thread-safe patterns.

## See Also

- [own-refcell-interior](./own-refcell-interior.md) — Full interior mutability guide
- [own-clone-explicit](./own-clone-explicit.md) — Use explicit Clone for meaningful costs
- [own-borrow-over-clone](./own-borrow-over-clone.md) — Prefer borrowing over cloning

## References

- [Rust 1.88.0 release notes](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0.html)
- [`std::cell::Cell::update`](https://doc.rust-lang.org/stable/std/cell/struct.Cell.html#method.update)
- [own-refcell-interior](own-refcell-interior.md) — Full interior mutability guide
- [own-copy-small](own-copy-small.md) — When to implement Copy
