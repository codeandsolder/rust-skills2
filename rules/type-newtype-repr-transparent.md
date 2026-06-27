# type-newtype-repr-transparent

> Always add `#[repr(transparent)]` to single-field newtypes

**Rule**: `type-newtype-repr-transparent`

## Why It Matters

`#[repr(transparent)]` guarantees that a single-field newtype has the exact same memory layout as its inner type. Without it, the compiler may (but is not required to) give the newtype a different layout. "It works anyway" is relying on unspecified behavior that can change with compiler versions, optimization levels, or target architectures. Adding `#[repr(transparent)]` is a zero-cost annotation that makes the layout guarantee explicit, enables niche optimization (e.g., with `NonZero`), and allows safe transmutation between the newtype and its inner type.

## Bad

```rust
// No layout guarantee — works by accident, unspecified behavior
struct UserId(u64);

// Unsafe transmute relies on layout matching — may silently break
unsafe fn id_from_raw(raw: u64) -> UserId {
    std::mem::transmute(raw)  // No guarantee this works
}

// Option<Handle> with plain u64 — 16 bytes instead of 8
struct Handle(u64);
assert_eq!(std::mem::size_of::<Option<Handle>>(), 16);
```

## Good

```rust
// Layout guarantee — same as u64
#[repr(transparent)]
struct UserId(u64);

// Safe transmute — guaranteed by repr(transparent)
fn id_from_raw(raw: u64) -> UserId {
    // Safe because UserId has the exact same layout as u64
    unsafe { std::mem::transmute::<u64, UserId>(raw) }
}

// Niche optimization with NonZero
use core::num::NonZero;

#[repr(transparent)]
struct Handle(NonZero<u64>);

// Option<Handle> is 8 bytes — zero-cost! The None variant
// uses the zero bit pattern from NonZero<u64>'s niche.
assert_eq!(std::mem::size_of::<Option<Handle>>(), std::mem::size_of::<u64>());
```

## Guarantees

```rust
use core::mem::{size_of, align_of, transmute};

#[repr(transparent)]
struct Meters(f64);

// Same size
assert_eq!(size_of::<Meters>(), size_of::<f64>());

// Same alignment
assert_eq!(align_of::<Meters>(), align_of::<f64>());

// Same ABI — safe to pass where f64 expected
extern "C" fn measure(distance: Meters) -> f64 {
    distance.0
}

// Safe transmute in both directions
let m: Meters = transmute(3.14_f64);
let v: f64 = transmute(m);
```

## With `PhantomData`

`PhantomData<T>` is zero-sized and does not affect layout, so it's safe in `#[repr(transparent)]` newtypes:

```rust
use core::marker::PhantomData;
use core::num::NonZero;

#[repr(transparent)]
struct TypedHandle<T> {
    raw: NonZero<u64>,
    _marker: PhantomData<T>,
}

// Still 8 bytes, still niche-optimized
assert_eq!(size_of::<TypedHandle<String>>(), 8);
assert_eq!(size_of::<Option<TypedHandle<String>>>(), 8);
```

## Anti-Pattern: Omitting `#[repr(transparent)]`

```rust
// Anti-pattern: works today, but relies on unspecified compiler behavior
struct FileDescriptor(std::os::raw::c_int);

// Always add #[repr(transparent)] — zero cost, guaranteed layout
#[repr(transparent)]
struct FileDescriptor(std::os::raw::c_int);
```

The Rust compiler never guarantees layout for newtypes without `#[repr(transparent)]`. Future compiler versions, different optimization levels, or cross-compilation targets may produce different layouts.

## When to Apply

| Scenario | Apply `#[repr(transparent)]`? |
|----------|-------------------------------|
| Single-field tuple struct | Always |
| Single-field named struct | Always |
| Newtype used in FFI | Required (not optional) |
| Pure Rust newtype | Always (zero cost, guaranteed layout) |
| Multi-field struct | N/A (only for single-field) |
| Enum | N/A (only for single-variant types) |

## See Also

- [type-repr-transparent](./type-repr-transparent.md) — FFI-focused `#[repr(transparent)]` guide
- [type-newtype-ids](./type-newtype-ids.md) — ID newtypes
- [type-phantom-marker](./type-phantom-marker.md) — `PhantomData` usage in transparent newtypes
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — `NonZero` niche optimization
- [Rust Reference: repr(transparent)](https://doc.rust-lang.org/reference/type-layout.html#the-transparent-representation)
