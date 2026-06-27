# type-nonzero-intrinsics

> Use `NonZero<uN>` for non-zero integer invariants

**Rule**: `type-nonzero-intrinsics`

## Why It Matters

`core::num::NonZero<uN>` encodes "this integer is never zero" in the type system, eliminating null-pointer-like sentinel bugs at compile time. As a bonus, `Option<NonZero<uN>>` is guaranteed to be the same size as `uN` (zero-cost optional), because the compiler uses the zero bit pattern as the `None` discriminant. With Rust 1.85+, `NonZero` types gained parity with plain integers: `div_ceil`, `midpoint`, `checked_`/`wrapping_`/`saturating_` arithmetic, and `cast_signed`/`cast_unsigned` for safe signed↔unsigned conversion.

## Bad

```rust
use core::num::NonZeroU32;

// Sentinel zero value — every caller must remember to check
struct UserId(u32);

fn find_user(id: UserId) -> Option<User> {
    if id.0 == 0 {
        return None;  // Sentinel check required
    }
    // ...
}

// Wasted space — 8 bytes instead of 4
let maybe: Option<u32> = Some(42);
assert_eq!(std::mem::size_of_val(&maybe), 8);

// Manual zero-avoidance logic
fn midpoint(a: u32, b: u32) -> u32 {
    // Risk of overflow, no type-level guarantee
    a + (b - a) / 2
}
```

## Good

```rust
use core::num::NonZero;

// NonZero encodes the invariant in the type system
struct UserId(NonZero<u32>);

// Option<NonZero<u32>> is zero-cost (4 bytes, same as u32)
assert_eq!(std::mem::size_of::<Option<NonZero<u32>>>(), std::mem::size_of::<u32>());

// Arithmetic on NonZero (Rust 1.85+)
let a = NonZero::<u32>::new(10).unwrap();
let b = NonZero::<u32>::new(3).unwrap();

// div_ceil (Rust 1.92+)
assert_eq!(a.div_ceil(b).get(), 4);  // ceil(10/3) = 4

// midpoint (Rust 1.85+)
let mid = a.midpoint(b);
assert_eq!(mid.get(), 6);  // (10 + 3) / 2 = 6 (with overflow protection)

// Safe signed/unsigned conversion (Rust 1.87+)
let unsigned = NonZero::<u32>::new(42).unwrap();
let signed: NonZero<i32> = unsigned.cast_signed();    // Ok
let back: NonZero<u32> = signed.cast_unsigned();      // Ok
```

## `NonZero<char>` (Rust 1.89+)

```rust
use core::num::NonZero;

// NonZero<char> guarantees the char is not '\0'
let c = NonZero::<char>::new('R').unwrap();
assert!(c.is_ascii());

// Option<NonZero<char>> is same size as char (4 bytes)
assert_eq!(std::mem::size_of::<Option<NonZero<char>>>(), std::mem::size_of::<char>());
```

## Zero-Cost Optional Pattern

```rust
use core::num::NonZero;

// A handle that can't be zero — free Option optimization
#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Handle(NonZero<u64>);

impl Handle {
    pub fn new(value: u64) -> Option<Self> {
        Some(Self(NonZero::new(value)?))
    }

    pub fn get(self) -> u64 {
        self.0.get()
    }
}

// These are both 8 bytes!
assert_eq!(std::mem::size_of::<Handle>(), 8);
assert_eq!(std::mem::size_of::<Option<Handle>>(), 8);
assert_eq!(std::mem::size_of::<Option<Handle>>(), std::mem::size_of::<u64>());
```

## Complete Arithmetic API (Rust 1.92+)

```rust
use core::num::NonZero;

let n = NonZero::<u32>::new(7).unwrap();
let m = NonZero::<u32>::new(2).unwrap();

// All operations available on plain integers also exist on NonZero:
let _ = n.checked_add(5);
let _ = n.checked_mul(3);
let _ = n.saturating_sub(10);
let _ = n.wrapping_add(100);
let _ = n.overflowing_sub(20);

// NonZero-specific operations
assert_eq!(n.div_ceil(m).get(), 4);  // ceil(7/2) = 4
assert_eq!(n.midpoint(m).get(), 4);  // (7+2)/2 = 4
```

## See Also

- [type-newtype-ids](./type-newtype-ids.md) — ID newtypes
- [type-repr-transparent](./type-repr-transparent.md) — Layout guarantees for newtypes
- [mem-compact-string](./mem-compact-string.md) — Small string optimization
- [core::num::NonZero docs](https://doc.rust-lang.org/std/num/struct.NonZero.html)
