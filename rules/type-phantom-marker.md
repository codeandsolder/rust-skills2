# type-phantom-marker

> Use PhantomData to express actual ownership, borrowing, variance and auto-trait relationships without storing a value; use PhantomPinned for deliberate pinning invariants

## Why It Matters

A phantom marker is zero-sized and has alignment one. It influences compiler
reasoning about variance, drop checking and auto traits. It does not create
an object, run that object's destructor, establish a pointer's validity or
enforce an external resource contract. Pick the marker from the relationship
the type must actually express.

## Good: Distinguish Semantic IDs

<!-- rust-check: run -->
```rust
use std::marker::PhantomData;

struct Id<T> {
    raw: u64,
    category: PhantomData<fn() -> T>,
}

impl<T> Id<T> {
    fn new(raw: u64) -> Self {
        Self { raw, category: PhantomData }
    }
}

struct User;
struct Order;

fn user_number(id: Id<User>) -> u64 {
    id.raw
}

fn main() {
    assert_eq!(user_number(Id::new(17)), 17);
    let order = Id::<Order>::new(42);
    assert_eq!(order.raw, 42);
}
```

Here the generic parameter is only a category tag. A function-type marker
does not impose ownership of a T or inherit T's Send/Sync restrictions.
That is appropriate for an integer ID, not automatically for a foreign
resource whose operations may have thread-affinity requirements.

## Good: Express Actual Ownership

<!-- rust-check: run -->
```rust
use std::cell::Cell;
use std::marker::PhantomData;
use std::ptr::NonNull;

struct RawOwner<T> {
    ptr: NonNull<T>,
    owned: PhantomData<T>,
}

impl<T> RawOwner<T> {
    fn new(value: T) -> Self {
        Self { ptr: Box::into_non_null(Box::new(value)), owned: PhantomData }
    }
}

impl<T> Drop for RawOwner<T> {
    fn drop(&mut self) {
        // SAFETY: the private owner retains the unique live Box allocation;
        // no ownership transfer occurred, and this destructor runs at most once.
        drop(unsafe { Box::from_non_null(self.ptr) });
    }
}

struct CountDrop<'a>(&'a Cell<u32>);

impl Drop for CountDrop<'_> {
    fn drop(&mut self) {
        self.0.set(self.0.get() + 1);
    }
}

fn main() {
    let count = Cell::new(0);
    let owner = RawOwner::new(CountDrop(&count));
    assert_eq!(count.get(), 0);
    drop(owner);
    assert_eq!(count.get(), 1);
}
```

The marker represents ownership, but the destructor actually drops and
deallocates the value. The constructor establishes validity; the marker
cannot repair an arbitrary invalid pointer. This is an illustrative raw
ownership boundary, not a reason to replace ordinary Box with raw pointers.

## Good: Model a Borrowed Raw View

<!-- rust-check: run -->
```rust
use std::marker::PhantomData;

struct Borrowed<'a, T> {
    ptr: *const T,
    borrow: PhantomData<&'a T>,
}

impl<'a, T> Borrowed<'a, T> {
    fn new(value: &'a T) -> Self {
        Self { ptr: value, borrow: PhantomData }
    }

    fn get(&self) -> &'a T {
        // SAFETY: new obtained this pointer from a shared reference valid
        // for 'a; no method can change it or grant conflicting mutable access.
        unsafe { &*self.ptr }
    }
}

fn main() {
    let value = String::from("borrowed");
    let view = Borrowed::new(&value);
    assert_eq!(view.get(), "borrowed");
}
```

Prefer an ordinary reference when possible. A raw view needs the explicit
lifetime and aliasing proof regardless of its marker.

## Marker Semantics

| Marker | Variance in T | Drop-check relationship | Send/Sync effect |
|---|---|---|---|
| `PhantomData<T>` | Covariant | Ownership-like | Follows T |
| `PhantomData<&'a T>` | Covariant | Shared borrow | Follows shared-reference requirements |
| `PhantomData<&'a mut T>` | Invariant | Exclusive borrow | Follows mutable-reference requirements |
| `PhantomData<fn() -> T>` | Covariant | Non-owning type tag | Function-pointer auto traits |
| `PhantomData<fn(T)>` | Contravariant | Non-owning type tag | Function-pointer auto traits |
| `PhantomData<fn(T) -> T>` | Invariant | Non-owning type tag | Function-pointer auto traits |

These describe the marker field, not the complete containing type.
Other fields and bounds also matter. The full drop-check rules depend
on destructors and ownership; do not use a phantom marker to waive a
real lifetime requirement.

## Pinning Is a Separate Contract

`PhantomPinned` makes a containing type not automatically implement
Unpin. It does not make an ordinary unpinned value immovable on
construction. A pinning API must first establish the pinned address
and ensure no safe method can move or invalidate the relevant data
until destruction. Moving a Pin<Box<T>> handle is distinct from moving T.

<!-- rust-check: run -->
```rust
use std::marker::PhantomPinned;
use std::pin::Pin;

struct PinnedRecord {
    value: u32,
    pinned: PhantomPinned,
}

fn main() {
    let record: Pin<Box<PinnedRecord>> = Box::pin(PinnedRecord {
        value: 42,
        pinned: PhantomPinned,
    });
    let moved_handle = record;
    assert_eq!(moved_handle.as_ref().get_ref().value, 42);
}
```

Do not use a casually initialized self-reference as a pinning recipe.
Self-referential objects need an audited construction, projection, aliasing
and destruction contract. Prefer indices or independent ownership when
they express the same relationships without pointer invariants.

## See Also

- [unsafe-untrusted-safe-code](./unsafe-untrusted-safe-code.md)
- [unsafe-send-sync-manual](./unsafe-send-sync-manual.md)
- [type-repr-transparent](./type-repr-transparent.md)
- [api-typestate](./api-typestate.md)
- [Rustonomicon: PhantomData](https://doc.rust-lang.org/nomicon/phantom-data.html)
- [Pin](https://doc.rust-lang.org/std/pin/index.html)
