# num-nonzero

> Use `NonZero*` types to forbid zero and unlock the niche optimization

## Why It Matters

`NonZeroU32`, `NonZeroI64`, and their siblings (available for all integer primitives in `std::num`) make zero unrepresentable at the type level — safe construction must preserve the invariant; `NonZeroU32::new(n)` returns `Option<NonZeroU32>` and constants such as `NonZeroU32::MIN` are already nonzero. This pushes the zero-check to the construction site and eliminates defensive zero-checks throughout the rest of the code. As a bonus, the compiler uses the zero bit-pattern as a *niche*, so `Option<NonZeroU32>` is exactly the same size as `u32` — no overhead for the `Option` tag.

## Bad

```rust
// caller must remember never to pass 0, but nothing enforces it
fn divide(numerator: u32, denominator: u32) -> u32 {
    assert!(denominator != 0, "denominator must not be zero");
    numerator / denominator
}

// ID of 0 is "invalid" by convention — not enforced
struct Widget {
    id: u32,  // 0 means "not yet assigned" — stringly-typed convention
}
```

## Good

<!-- rust-check: run -->
```rust
use std::num::NonZeroU32;
use std::mem::size_of;

// zero is rejected at construction; division is always safe
fn divide(numerator: u32, denominator: NonZeroU32) -> u32 {
    numerator / denominator.get()
}

// ID is guaranteed nonzero; transparent layout preserves the Option niche.
#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct WidgetId(NonZeroU32);

impl WidgetId {
    /// Returns `None` if `id` is zero.
    pub fn new(id: u32) -> Option<Self> {
        NonZeroU32::new(id).map(WidgetId)
    }

    pub fn get(self) -> u32 {
        self.0.get()
    }
}

fn main() {
    assert!(NonZeroU32::new(0).is_none());
    assert_eq!(NonZeroU32::new(1), Some(NonZeroU32::MIN));
    assert_eq!(size_of::<Option<NonZeroU32>>(), size_of::<u32>());
    assert_eq!(size_of::<Option<WidgetId>>(), size_of::<u32>());
    assert_eq!(size_of::<Result<WidgetId, ()>>(), size_of::<u32>());
    assert!(WidgetId::new(0).is_none());
    assert_eq!(WidgetId::new(42).map(WidgetId::get), Some(42));
    assert_eq!(NonZeroU32::new(3).map(|d| divide(12, d)), Some(4));
    // Signed division has another failure mode despite a nonzero divisor.
    assert_eq!(i32::MIN.checked_div(-1), None);
}
```

## Key Points

- All `NonZero*` types live in `std::num`: `NonZeroU8`, `NonZeroU16`, `NonZeroU32`, `NonZeroU64`, `NonZeroU128`, `NonZeroUsize`, and their signed counterparts.
- **Construction**: `NonZeroU32::new(n) -> Option<NonZeroU32>`. Use a checked construction path for runtime inputs; use a nonzero constant for a statically known bound. Do not introduce panic extraction.
- **Access**: `.get()` returns the inner primitive value.
- **Arithmetic**: `NonZeroU32` does not implement `Add`/`Sub` directly (the result could be zero). Use its invariant-preserving methods, such as unsigned checked_add or saturating_add, when they express the intended operation. Other operations may require checking the primitive result and reconstructing the type. Signed division still has MIN / -1 overflow.
- **Niche optimization** is guaranteed for Option of the documented NonZero primitive types and transparent wrappers; Result has an analogous documented guarantee when the other variant is an appropriate alignment-one zero-sized type (such as ()). Arbitrary Result payloads or wrapper layouts have no such unconditional guarantee.

## See Also

- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — invariant-aware arithmetic

- [type-newtype-ids](type-newtype-ids.md) - wrap IDs in newtypes for type-safe distinctions
- [mem-smaller-integers](mem-smaller-integers.md) - use the smallest integer type that fits
