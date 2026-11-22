# type-repr-transparent

> Use `#[repr(transparent)]` when a wrapper intentionally needs the wrapped field's layout and ABI

**Rule**: `type-repr-transparent`

## Why It Matters

`#[repr(transparent)]` is an interoperability and layout contract, not a default annotation for every newtype. It is useful when a wrapper must deliberately have the same layout and ABI as its non-zero-sized field, especially at FFI boundaries or in carefully documented unsafe abstractions.

For ordinary pure-Rust newtypes, the compiler is free to choose layout and callers should not depend on it. That is normally a feature: it leaves implementation freedom and avoids promising ABI properties that the API does not need.

`#[repr(transparent)]` also does **not** make `transmute` safe. `std::mem::transmute` remains an unsafe operation, and both the source and destination values must satisfy their types' validity requirements.

## Bad

```rust
// No external layout contract exists, so promising one adds no value.
#[repr(transparent)]
struct UserId(u64);

// Wrong reason: repr(transparent) does not turn transmute into a safe operation.
#[repr(transparent)]
struct Meters(f64);

fn meters_from_raw(raw: f64) -> Meters {
    unsafe { std::mem::transmute(raw) }
}
```

Prefer the ordinary constructor when you own the type:

```rust
struct Meters(f64);

fn meters_from_raw(raw: f64) -> Meters {
    Meters(raw)
}
```

## Good: A Deliberate Foreign ABI Value

<!-- rust-check: run -->
```rust
use std::ffi::c_int;
use std::mem::{align_of, size_of};

// Numeric foreign handle representation, not ownership of a live resource.
#[repr(transparent)]
struct RawHandle(c_int);

fn main() {
    assert_eq!(size_of::<RawHandle>(), size_of::<c_int>());
    assert_eq!(align_of::<RawHandle>(), align_of::<c_int>());
    assert_eq!(RawHandle(7).0, 7);
}
```

If a foreign interface passes C int values by value, the transparent
wrapper can deliberately match that ABI. It does not establish descriptor
validity or ownership. For Unix file descriptors, use standard-library
OwnedFd/BorrowedFd and safe File APIs internally instead of reimplementing
open/close or hardcoding platform-specific flags.

## What It Guarantees

For a transparent struct or single-variant enum, Rust permits at most one field that is not zero-sized with alignment 1. The transparent type has the same layout and ABI as that field, or as unit if no such field exists. Layout alone does not make every underlying bit pattern a valid wrapper value.

```rust
use std::mem::{align_of, size_of};

#[repr(transparent)]
struct Handle(u64);

assert_eq!(size_of::<Handle>(), size_of::<u64>());
assert_eq!(align_of::<Handle>(), align_of::<u64>());
```

Zero-sized marker fields can be included when they satisfy the transparent-representation restrictions:

```rust
use std::marker::PhantomData;

#[repr(transparent)]
struct TypedHandle<T> {
    raw: u64,
    marker: PhantomData<T>,
}
```

## When to Apply

| Scenario | Recommendation |
|----------|----------------|
| FFI wrapper that must match the wrapped ABI | Use `#[repr(transparent)]` |
| Unsafe abstraction whose documented contract depends on layout | Usually use it and document the invariant |
| Pure-Rust semantic newtype | Usually omit it unless layout is intentionally part of the contract |
| "I might want to transmute this later" | Not a sufficient reason |
| Multi-field data structure | Use the representation appropriate to the actual ABI/layout requirement |

## Key Points

- Treat a publicly documented transparent representation as an intentional ABI promise. For external consumers, document the relevant field layout; do not infer a stable public contract from private fields alone.
- Do not add it automatically to every one-field newtype.
- `transmute` remains unsafe; layout compatibility is only one of its requirements.
- Prefer constructors and conversion traits over transmutation when you control the wrapper type.

## See Also

- [Rust Reference: repr(transparent)](https://doc.rust-lang.org/reference/type-layout.html#the-transparent-representation)
- [type-newtype-ids](./type-newtype-ids.md) — Newtype pattern
- [type-phantom-marker](./type-phantom-marker.md) — `PhantomData` usage
- [api-newtype-safety](./api-newtype-safety.md) — Type-safe newtypes
- [unsafe-extern-block](./unsafe-extern-block.md) — Edition 2024 FFI declarations
