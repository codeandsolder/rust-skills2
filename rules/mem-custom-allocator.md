# mem-custom-allocator

> Use stable Rust 1.100 allocator-aware `Vec` and `Box` when allocation ownership or placement is part of the API contract

**Rule**: `mem-custom-allocator`

## Why It Matters

Rust 1.100 stabilizes the core `std::alloc::Allocator` trait, `Global` and `System`, and allocator-parametric `Vec<T, A>` / `Box<T, A>` construction and ownership handoffs. This makes custom-allocator use a stable library design option, not an excuse to implement an ad hoc ownership model.

Choose a custom allocator only when its lifetime, reclamation, locality, fallibility, or accounting is actually needed. `Vec<T>` and `Box<T>` with the global allocator remain excellent defaults. Not every collection or pointer constructor is allocator-generic yet.

## Good: Carry the Allocator in the Type

```rust
use std::alloc::System;

fn main() {
    let mut values = Vec::with_capacity_in(4, System);
    values.extend([2_u32, 3, 5]);
    assert_eq!(values.as_slice(), &[2, 3, 5]);
    let boxed = Box::new_in(17, System);
    assert_eq!(*boxed, 17);
}
```

A `Vec<T, A>` and `Box<T, A>` retain the allocator as part of their owner type. Do not reconstruct the same allocation with a different allocator.

## Raw Handoffs Are an Unsafe Contract

Rust 1.100 includes `Vec::into_raw_parts_with_allocator` / `Vec::from_raw_parts_in`, `Vec::into_parts_with_allocator` / `Vec::from_parts_in`, `Box::into_raw_with_allocator` / `Box::from_raw_in`, and non-null alternatives.

Preserve the returned allocator alongside pointer, length, capacity, and element layout. A mismatch can cause undefined behavior. Prefer handing off the owning `Vec`/`Box` directly; use raw parts only at an FFI boundary or another proven ownership transfer.

Implementing `Allocator` is unsafe and requires satisfying its allocation/deallocation, alignment, ownership, and grow/shrink contracts. It is not simply a wrapper around an arbitrary memory pool. Treat deallocation by the wrong allocator as a soundness bug.

## Fallible Paths and Scope

Custom allocation does not make an infallible `Vec::push` automatically return allocation errors. Choose `try_reserve` and allocator-specific fallible operations for recoverable exhaustion, and preserve allocation errors rather than assuming every allocator grows indefinitely.

The stabilized surface is narrower than the old nightly `allocator_api` feature: verify an individual collection and method are stable on 1.100 before recommending them.

## See Also

- [mem-arena-allocator](./mem-arena-allocator.md) — arena lifetime and destructor trade-offs
- [unsafe-strict-provenance](./unsafe-strict-provenance.md) — pointer and ownership handoffs
- [proj-msrv-declare](./proj-msrv-declare.md) — compatibility contracts
- [Rust 1.100 release notes](https://doc.rust-lang.org/releases.html#version-11000-2026-11-12)
