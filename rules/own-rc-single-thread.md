# own-rc-single-thread

> Use `Rc<T>` for shared ownership in single-threaded contexts

## Why It Matters

`Rc<T>` (Reference Counted) provides shared ownership without the atomic overhead of `Arc<T>`. In single-threaded code, `Rc` is faster because it uses non-atomic reference counting. Using `Arc` when you don't need thread-safety wastes CPU cycles on unnecessary synchronization.

## Bad

```rust
use std::sync::Arc;

// Single-threaded application using Arc unnecessarily
fn build_tree() -> Arc<Node> {
    let root = Arc::new(Node::new("root"));
    let child1 = Arc::new(Node::new("child1"));
    let child2 = Arc::new(Node::new("child2"));
    
    // All in same thread, but paying atomic overhead
    root.add_child(child1.clone());
    root.add_child(child2.clone());
    root
}
```

Atomic operations have measurable overhead even without contention.

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use std::rc::Rc;

// Single-threaded: use Rc for zero atomic overhead
fn build_tree() -> Rc<Node> {
    let root = Rc::new(Node::new("root"));
    let child1 = Rc::new(Node::new("child1"));
    let child2 = Rc::new(Node::new("child2"));
    
    root.add_child(child1.clone());
    root.add_child(child2.clone());
    root
}

// Compiler enforces single-thread: Rc is !Send + !Sync
// Attempting to send across threads = compile error
```

## Decision Guide

| Scenario | Use |
|----------|-----|
| Single-threaded, shared ownership | `Rc<T>` |
| Multi-threaded, shared ownership | `Arc<T>` |
| Single owner, might need multiple later | Start with `Rc`, upgrade if needed |
| Library code, unknown threading model | `Arc<T>` (safer default) |

## Recent Additions

### `Rc::new_zeroed` / `Rc::new_zeroed_slice` (1.92)

```rust
use std::rc::Rc;

// 1.92+: allocate zeroed Rc, avoids double-initialization
let buf = unsafe { Rc::new_zeroed::<LargeBuf>() };
let buf = unsafe { buf.assume_init() }; // Now safe to use
```

### `Pin<Rc<T>>` Default (1.91)

```rust
use std::pin::Pin;
use std::rc::Rc;

// 1.91+: Pin<Rc<T>> implements Default when T: Default
fn create_pinned() -> Pin<Rc<MyData>> {
    Default::default()
}
```

### `Cell::as_array_of_cells` with `Rc<Cell<[T; N]>>` (1.91)

```rust
use std::cell::Cell;
use std::rc::Rc;

// 1.91+: reinterpret &Cell<[T; N]> as &[Cell<T>; N]
let data: Rc<Cell<[u32; 4]>> = Rc::new(Cell::new([1, 2, 3, 4]));
let cells: &[Cell<u32>; 4] = data.as_array_of_cells();

// Mutate individual elements through the cell
cells[0].set(10);
cells[1].set(20);
// This was previously impossible without unsafe code
```

## See Also

- [own-arc-shared](./own-arc-shared.md) - When you need thread-safe sharing
- [own-refcell-interior](./own-refcell-interior.md) - Combining Rc with interior mutability
- [own-cell-update](./own-cell-update.md) - Cell::update for Copy types
