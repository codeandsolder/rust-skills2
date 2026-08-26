# type-newtype-repr-transparent

> Use `#[repr(transparent)]` only when a newtype intentionally promises the wrapped field's layout or ABI

**Rule**: `type-newtype-repr-transparent`

## Why It Matters

A newtype is primarily a type-safety tool. Most pure-Rust newtypes do not need a representation attribute: callers should use constructors and conversion traits rather than depend on layout.

`#[repr(transparent)]` is appropriate when layout or ABI compatibility with the wrapped field is deliberately part of the contract, especially for FFI and some unsafe abstractions. It does not make `transmute` safe; validity requirements still apply and `transmute` remains an unsafe operation.

## Pure Rust: Usually No Representation Promise

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct UserId(u64);

impl From<u64> for UserId {
    fn from(raw: u64) -> Self {
        Self(raw)
    }
}
```

There is no benefit in promising a stable ABI here unless some external contract actually needs one.

## FFI/Layout Contract: Use `repr(transparent)`

```rust
use core::ffi::c_int;

#[repr(transparent)]
struct FileDescriptor(c_int);
```

Now `FileDescriptor` intentionally has the layout and ABI of its transparent field, subject to the restrictions in the Rust Reference.

## Do Not Call Transmutation "Safe"

```rust
#[repr(transparent)]
struct Meters(f64);

fn meters_from_raw(raw: f64) -> Meters {
    // Prefer the constructor when you own the type.
    Meters(raw)
}
```

Even between layout-compatible types, `std::mem::transmute` is still `unsafe` and must preserve the destination type's validity invariants.

## When to Apply

| Scenario | Recommendation |
|---|---|
| Ordinary semantic newtype | Usually omit `repr` |
| FFI wrapper that must match the wrapped ABI | Use `#[repr(transparent)]` |
| Unsafe abstraction whose contract depends on layout | Use it when the transparent guarantee is the required one, and document why |
| "Maybe I will transmute it later" | Not a sufficient reason |

## Key Points

- A representation attribute is an API/layout commitment, not a default decoration.
- `repr(transparent)` guarantees layout/ABI compatibility; it does not waive type validity rules.
- Prefer constructors, `From`, and `TryFrom` over transmutation when you control both sides.
- Keep the canonical detailed guidance in [type-repr-transparent](./type-repr-transparent.md).

## See Also

- [type-repr-transparent](./type-repr-transparent.md) — canonical transparent-representation guidance
- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-phantom-marker](./type-phantom-marker.md) — marker fields and variance
- [Rust Reference: transparent representation](https://doc.rust-lang.org/reference/type-layout.html#the-transparent-representation)
