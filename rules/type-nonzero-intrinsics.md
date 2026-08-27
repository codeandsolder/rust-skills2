# type-nonzero-intrinsics

> Use `NonZero<T>` when zero is invalid, and use only operations whose result semantics preserve that invariant

**Rule**: `type-nonzero-intrinsics`

## Why It Matters

`core::num::NonZero<T>` makes “not zero” part of the value's validity invariant. For supported primitive types, the all-zero bit pattern is excluded, which gives `Option<NonZero<T>>` a guaranteed niche representation without an additional discriminant.

That invariant also shapes the arithmetic API. `NonZero` does **not** simply expose every method of the underlying integer: operations are provided when their signatures/results can express overflow or otherwise preserve non-zero validity.

## Good: Encode the Invariant Once

```rust
use core::num::NonZero;

#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct WorkerId(NonZero<u32>);

impl WorkerId {
    fn new(raw: u32) -> Option<Self> {
        NonZero::new(raw).map(Self)
    }

    fn get(self) -> u32 {
        self.0.get()
    }
}

fn main() {
    assert!(WorkerId::new(0).is_none());
    assert_eq!(WorkerId::new(7).unwrap().get(), 7);

    assert_eq!(
        core::mem::size_of::<Option<WorkerId>>(),
        core::mem::size_of::<u32>(),
    );
}
```

The size/layout optimization is useful, but the primary benefit is semantic: safe code holding a `WorkerId` does not need to re-check for zero.

## Arithmetic Is Invariant-Aware, Not Full Integer Parity

Unsigned `NonZero` integers provide operations whose return types account for overflow while preserving non-zero results.

```rust
use core::num::NonZero;

fn main() {
    let seven = NonZero::<u32>::new(7).unwrap();
    let two = NonZero::<u32>::new(2).unwrap();

    assert_eq!(seven.checked_add(5).unwrap().get(), 12);
    assert_eq!(NonZero::<u32>::MAX.checked_add(1), None);
    assert_eq!(NonZero::<u32>::MAX.saturating_add(1), NonZero::<u32>::MAX);

    assert_eq!(seven.div_ceil(two).get(), 4);
    assert_eq!(seven.midpoint(two).get(), 4);
}
```

Do not claim that every wrapping/overflowing/subtraction method from `u32` has a corresponding `NonZero<u32>` method. An operation that can naturally produce zero may need to return `Option`, use a different operand/result shape, or be performed on the underlying integer followed by explicit reconstruction.

For example, if wrapping semantics are genuinely required:

```rust
use core::num::NonZero;

fn wrapping_add_nonzero(value: NonZero<u32>, amount: u32) -> Option<NonZero<u32>> {
    NonZero::new(value.get().wrapping_add(amount))
}

fn main() {
    let max = NonZero::<u32>::MAX;
    assert!(wrapping_add_nonzero(max, 1).is_none());
}
```

The `Option` is important: ordinary integer wrapping can land exactly on zero, which cannot be represented as `NonZero<u32>`.

## Signed/Unsigned Casts Reinterpret the Bit Pattern

`cast_signed` / `cast_unsigned` preserve the bits and switch to the same-width signed/unsigned `NonZero` type. They are **not** range-checked numerical conversions.

```rust
use core::num::NonZero;

fn main() {
    let all_bits = NonZero::<u32>::new(u32::MAX).unwrap();
    let signed = all_bits.cast_signed();
    assert_eq!(signed.get(), -1);

    let minus_one = NonZero::<i32>::new(-1).unwrap();
    let unsigned = minus_one.cast_unsigned();
    assert_eq!(unsigned.get(), u32::MAX);
}
```

Use `TryFrom`/`try_into` when the requirement is numeric range preservation rather than bit reinterpretation.

## `NonZero<char>`

`NonZero<char>` represents any Unicode scalar value except `'\0'`.

```rust
use core::num::NonZero;

fn main() {
    let c = NonZero::<char>::new('R').unwrap();
    assert!(c.get().is_ascii());
    assert!(NonZero::<char>::new('\0').is_none());

    assert_eq!(
        core::mem::size_of::<Option<NonZero<char>>>(),
        core::mem::size_of::<char>(),
    );
}
```

Methods of `char` are reached through `.get()`; `NonZero<char>` is not itself a `char` and does not transparently forward the full `char` method set.

## Construction and Unsafe Construction

Prefer `NonZero::new(value)` when zero is possible at runtime. Use `new_unchecked` only when a local proof already establishes non-zero; passing zero to it is undefined behavior.

```rust
use core::num::NonZero;

fn main() {
    let runtime = 42u32;
    let checked = NonZero::new(runtime).expect("42 is non-zero");
    assert_eq!(checked.get(), 42);

    // SAFETY: the literal 7 is non-zero.
    let constant = unsafe { NonZero::<u32>::new_unchecked(7) };
    assert_eq!(constant.get(), 7);
}
```

For constants, prefer stable const construction patterns that keep the proof obvious; unsafe construction should not be used merely to save an `Option` match in ordinary runtime code.

## Layout Is a Real Contract; Arithmetic Surface Is Versioned API

The niche/layout guarantee for `Option<NonZero<T>>` is part of the type's documented representation contract. The set of convenience methods, however, evolves with Rust releases and differs between signed, unsigned, and non-integer `NonZero` instantiations.

When adding a “recent API” example, check the current standard-library documentation for the exact receiver, operand, result type, and stabilization status rather than extrapolating from primitive integers.

## See Also

- [type-newtype-ids](./type-newtype-ids.md) — semantic IDs
- [type-newtype-validated](./type-newtype-validated.md) — checked construction
- [type-repr-transparent](./type-repr-transparent.md) — layout promises for wrappers

## References

- [core::num::NonZero](https://doc.rust-lang.org/core/num/struct.NonZero.html)
