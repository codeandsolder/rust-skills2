# unsafe-cell-access

> Treat Rust 1.100 `UnsafeCell` accessors as explicit aliasing contracts, not as permission to manufacture simultaneous references

**Rule**: `unsafe-cell-access`

## Why It Matters

Rust 1.100 stabilizes `UnsafeCell::replace`, `UnsafeCell::as_ref_unchecked` and `UnsafeCell::as_mut_unchecked`. The dedicated accessors can simplify a carefully audited interior-mutability abstraction, but `UnsafeCell` relaxes only the immutability guarantee of shared references. It does not suspend Rust's reference aliasing rules or thread-safety requirements.

Prefer ordinary `&mut T` or `UnsafeCell::get_mut` when unique ownership is already proven; prefer `Cell`, `RefCell` or a synchronization primitive when their contracts fit.

## Good: Exclusive Access With an Explicit Proof

```rust
use std::cell::UnsafeCell;

fn main() {
    let mut cell = UnsafeCell::new(8_u32);
    // Unique mutable access through the owning variable: no aliasing possible.
    assert_eq!(*cell.get_mut(), 8);
    *cell.get_mut() = 13;
    assert_eq!(cell.into_inner(), 13);
}
```

When using the new unchecked helpers, prove absence of conflicting references for the entire resulting borrow. `UnsafeCell::replace` is not an atomic replacement; it does not make concurrent access safe.

## Review Checklist

- The required lifetime and exclusivity of any returned reference are established.
- No outstanding shared reference is invalidated by writing through the cell.
- No unsynchronized cross-thread read/write is introduced.
- Panic paths and destructors respect initialization and ownership.
- A `SAFETY:` comment explains the actual invariant, not merely "inside UnsafeCell".

## See Also

- [own-refcell-interior](./own-refcell-interior.md) — checked single-thread interior mutability
- [unsafe-minimize-scope](./unsafe-minimize-scope.md) — keep unsafe localized
- [unsafe-send-sync-manual](./unsafe-send-sync-manual.md) — thread safety
