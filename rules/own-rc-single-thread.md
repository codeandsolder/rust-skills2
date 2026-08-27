# own-rc-single-thread

> Use `Rc<T>` for shared ownership that is confined to one thread

## Why It Matters

`Rc<T>` provides reference-counted ownership without atomic reference-count operations. It is intentionally `!Send` and `!Sync`, so the type system prevents an `Rc` ownership graph from crossing thread boundaries.

Choose `Rc` when the ownership model is genuinely single-threaded. Choose `Arc` when owners must cross threads. Do not select either solely from a blanket performance rule; the threading and ownership contract comes first.

## Bad: Pay for Thread-Safe Ownership You Do Not Need

```rust
use std::sync::Arc;

fn main() {
    let root = Arc::new(String::from("root"));
    let left = Arc::clone(&root);
    let right = Arc::clone(&root);

    assert_eq!(&*left, "root");
    assert_eq!(&*right, "root");
}
```

This is correct Rust, but if the entire ownership graph is permanently single-threaded, `Rc` expresses that constraint more directly and avoids atomic reference-count updates.

## Good: Single-Threaded Shared Ownership

```rust
use std::rc::Rc;

#[derive(Debug)]
struct Node {
    name: String,
}

fn main() {
    let node = Rc::new(Node { name: "root".into() });
    let left = Rc::clone(&node);
    let right = Rc::clone(&node);

    assert_eq!(left.name, "root");
    assert_eq!(right.name, "root");
    assert_eq!(Rc::strong_count(&node), 3);
}
```

`Rc::clone(&value)` makes the ownership operation visually explicit and is conventional when cloning the pointee itself would mean something different.

## Interior Mutability When the Graph Needs Mutation

`Rc<T>` alone only gives shared ownership. For single-threaded shared mutation, pair it with an interior-mutability type whose runtime semantics fit the problem.

```rust
use std::cell::RefCell;
use std::rc::Rc;

fn main() {
    let values = Rc::new(RefCell::new(vec![1, 2]));
    let other = Rc::clone(&values);

    other.borrow_mut().push(3);
    assert_eq!(&*values.borrow(), &[1, 2, 3]);
}
```

`RefCell` dynamically checks the usual one-mutable-or-many-shared borrowing rule and panics on violations. It is not a synchronization primitive.

## Cycles Need Weak References

Strong `Rc` cycles leak because every node in the cycle keeps another strong owner alive. Use `Weak<T>` for non-owning back-references or other edges that should not contribute to lifetime.

```rust
use std::rc::{Rc, Weak};

fn main() {
    let owner = Rc::new(String::from("resource"));
    let observer: Weak<String> = Rc::downgrade(&owner);

    let upgraded = observer.upgrade().unwrap();
    assert_eq!(&*upgraded, "resource");
    drop(upgraded);

    drop(owner);
    assert!(observer.upgrade().is_none());
}
```

## Zeroed and Uninitialized Allocation APIs

Current stable Rust exposes `Rc` constructors that return `MaybeUninit` storage. The allocation itself is safe; `assume_init` is unsafe because that is where validity is asserted.

```rust
use std::rc::Rc;

fn main() {
    let zero = Rc::<u32>::new_zeroed();
    // SAFETY: the all-zero bit pattern is a valid u32.
    let zero = unsafe { zero.assume_init() };
    assert_eq!(*zero, 0);

    let zeros = Rc::<[u32]>::new_zeroed_slice(3);
    // SAFETY: every zeroed element is a valid initialized u32.
    let zeros = unsafe { zeros.assume_init() };
    assert_eq!(&*zeros, &[0, 0, 0]);
}
```

Do not generalize that example to arbitrary `T`: all-zero bytes are invalid for references, `NonZero` integers, many enums, and other types.

For full overwrite, initialize uninitialized storage directly:

```rust
use std::rc::Rc;

fn main() {
    let mut values = Rc::<[u32]>::new_uninit_slice(2);
    let slots = Rc::get_mut(&mut values).unwrap();
    slots[0].write(7);
    slots[1].write(9);

    // SAFETY: both elements were initialized above.
    let values = unsafe { values.assume_init() };
    assert_eq!(&*values, &[7, 9]);
}
```

Use ordinary `Rc::new(value)` unless deferred/in-place initialization solves a real problem.

## `Cell<[T; N]>` Element Access

`Cell::as_array_of_cells` gives an array-shaped view of the element cells while preserving `Cell`'s single-threaded interior-mutability rules.

```rust
use std::cell::Cell;
use std::rc::Rc;

fn main() {
    let data: Rc<Cell<[u32; 4]>> = Rc::new(Cell::new([1, 2, 3, 4]));
    let cells: &[Cell<u32>; 4] = data.as_array_of_cells();

    cells[0].set(10);
    cells[1].set(20);
    assert_eq!(data.get(), [10, 20, 3, 4]);
}
```

The exact array-returning convenience is newer than the long-standing slice-of-cells API; it is not accurate to claim element-wise `Cell` access was previously impossible without unsafe code.

## `Rc` vs `Arc`

| Requirement | Typical choice |
|---|---|
| Shared ownership, one thread | `Rc<T>` |
| Shared ownership across threads | `Arc<T>` |
| No shared ownership needed | owned value / borrow |
| Single-threaded shared mutation | often `Rc<RefCell<T>>`, `Rc<Cell<T>>`, or a domain-specific design |
| Cross-thread mutation | `Arc` plus an appropriate synchronization/concurrent abstraction |

Library code should expose the semantics it needs rather than defaulting to `Arc` merely because callers might someday use threads.

## See Also

- [own-arc-shared](./own-arc-shared.md) — cross-thread shared ownership
- [own-refcell-interior](./own-refcell-interior.md) — runtime borrow checking
- [own-cell-update](./own-cell-update.md) — `Cell` updates
- [unsafe-maybeuninit](./unsafe-maybeuninit.md) — initialization validity
