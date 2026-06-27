# type-phantom-marker

> Use `PhantomData` for zero-cost type markers

**Rule**: `type-phantom-marker`

## Why It Matters

Sometimes your type needs to be parameterized by a type that doesn't appear in any field — for variance, drop order, or semantic purposes. `PhantomData<T>` tells the compiler your type is "associated with" `T` without storing any `T` data. It has zero runtime cost. For `!Unpin` markers, use `PhantomPinned`, a dedicated zero-sized type from `std::marker`.

## Bad

```rust
// Type parameter unused — compiler error
struct Handle<T> {
    id: u64,
    // Error: parameter `T` is never used
}

// Workaround with unnecessary storage
struct Handle<T> {
    id: u64,
    _type: Option<T>,  // Wastes memory, requires T: Default
}
```

## Good

```rust
use std::marker::PhantomData;

struct Handle<T> {
    id: u64,
    _marker: PhantomData<T>,  // Zero-size, tells compiler about T
}

impl<T> Handle<T> {
    fn new(id: u64) -> Self {
        Handle { id, _marker: PhantomData }
    }
}

// Different Handle types are incompatible
struct User;
struct Order;

fn process_user(h: Handle<User>) { ... }

let user_handle = Handle::<User>::new(1);
let order_handle = Handle::<Order>::new(2);

process_user(user_handle);   // OK
// process_user(order_handle);  // Error: expected Handle<User>, found Handle<Order>
```

## Expressing Ownership

```rust
use std::marker::PhantomData;

// Owns T conceptually (like Box<T>)
struct Container<T> {
    ptr: *mut T,
    _marker: PhantomData<T>,  // Drop will be called on T
}

impl<T> Drop for Container<T> {
    fn drop(&mut self) {
        unsafe { std::ptr::drop_in_place(self.ptr); }
    }
}
```

## Expressing Borrowing

```rust
use std::marker::PhantomData;

// Borrows T for lifetime 'a
struct Ref<'a, T> {
    ptr: *const T,
    _marker: PhantomData<&'a T>,  // Acts like &'a T
}

impl<'a, T> Ref<'a, T> {
    fn get(&self) -> &'a T {
        unsafe { &*self.ptr }
    }
}
```

## `PhantomPinned` for `!Unpin` Markers

`PhantomPinned` is a zero-sized type that implements `!Unpin`, making your type immovable after construction — essential for self-referential structs and pinned futures:

```rust
use std::marker::PhantomPinned;
use std::pin::Pin;

// A type that, once pinned, cannot be moved
struct SelfReferential {
    data: String,
    pointer: *const String,  // Points to `self.data`
    _pin: PhantomPinned,      // Makes the type !Unpin
}

impl SelfReferential {
    fn new(data: String) -> Pin<Box<Self>> {
        let mut s = Box::pin(SelfReferential {
            pointer: std::ptr::null(),
            data,
            _pin: PhantomPinned,
        });
        // Safety: we won't move `s` after initializing the pointer
        unsafe {
            let this: &mut Self = Pin::as_mut(&mut s).get_unchecked_mut();
            this.pointer = &this.data as *const String;
        }
        s
    }
}
```

## `#[repr(transparent)]` + `PhantomData` + `NonZero<uN>` for FFI Handles

Combine all three for a type-safe, niche-optimized FFI handle:

```rust
use std::marker::PhantomData;
use std::num::NonZero;

/// A type-safe, non-nullable, niche-optimized FFI handle.
#[repr(transparent)]
struct FfiHandle<T> {
    raw: NonZero<u64>,
    _marker: PhantomData<T>,
}

impl<T> FfiHandle<T> {
    /// Create a handle from a raw non-zero value.
    ///
    /// # Safety
    /// `raw` must be a valid handle returned by the C library.
    unsafe fn from_raw(raw: NonZero<u64>) -> Self {
        Self { raw, _marker: PhantomData }
    }

    fn as_raw(&self) -> NonZero<u64> {
        self.raw
    }
}

// Zero-cost optional: Option<FfiHandle<T>> is 8 bytes
assert_eq!(std::mem::size_of::<FfiHandle<()>>(), 8);
assert_eq!(std::mem::size_of::<Option<FfiHandle<()>>>(), 8);
```

## Type-Level State Machine

```rust
use std::marker::PhantomData;

struct Unlocked;
struct Locked;

struct Door<State> {
    _state: PhantomData<State>,
}

impl Door<Unlocked> {
    fn lock(self) -> Door<Locked> {
        println!("Locking...");
        Door { _state: PhantomData }
    }

    fn open(&self) { println!("Opening..."); }
}

impl Door<Locked> {
    fn unlock(self) -> Door<Unlocked> {
        println!("Unlocking...");
        Door { _state: PhantomData }
    }
    // Can't call open() on Locked door — method doesn't exist
}

let door: Door<Unlocked> = Door { _state: PhantomData };
door.open();             // OK
let locked = door.lock();
// locked.open();        // Error: no method `open` for Door<Locked>
let unlocked = locked.unlock();
unlocked.open();         // OK
```

## Variance Control

```rust
use std::marker::PhantomData;

// Covariant in T (PhantomData<T>)
struct Producer<T> { _marker: PhantomData<T> }

// Contravariant in T (PhantomData<fn(T)>)
struct Consumer<T> { _marker: PhantomData<fn(T)> }

// Invariant in T (PhantomData<fn(T) -> T>)
struct Both<T> { _marker: PhantomData<fn(T) -> T> }
```

## Common Uses

```rust
// 1. FFI handles with type safety
struct FileHandle<T: FileType> {
    fd: i32,
    _marker: PhantomData<T>,
}

// 2. Generic iterators
struct Iter<'a, T> {
    ptr: *const T,
    end: *const T,
    _marker: PhantomData<&'a T>,
}

// 3. Allocator-aware types
struct Vec<T, A: Allocator = Global> {
    buf: RawVec<T, A>,
    len: usize,
}
```

## See Also

- [Rust Reference: PhantomData](https://doc.rust-lang.org/reference/special-types-and-traits.html#phantomdata)
- [PhantomPinned docs](https://doc.rust-lang.org/std/marker/struct.PhantomPinned.html)
- [Pin and PhantomPinned](https://doc.rust-lang.org/std/pin/index.html)
- [api-typestate](./api-typestate.md) — State machine pattern
- [api-newtype-safety](./api-newtype-safety.md) — Type-safe wrappers
- [type-newtype-ids](./type-newtype-ids.md) — ID types
- [type-repr-transparent](./type-repr-transparent.md) — Layout guarantees
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — NonZero niche optimization
