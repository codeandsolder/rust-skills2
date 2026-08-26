# unsafe-maybeuninit

> Use `MaybeUninit<T>` for uninitialized memory; never use `mem::uninitialized()` or `mem::zeroed()` for types with validity invariants.

## Why It Matters

Producing an invalid value of `T` is undefined behavior even if code intends to overwrite it immediately. `MaybeUninit<T>` lets memory exist before a valid `T` has been constructed there.

The condition for `assume_init` is **not** "every byte has been initialized." Padding bytes may legitimately remain uninitialized. The requirement is that the memory contains a fully initialized value satisfying all of `T`'s validity requirements.

## Good: Single Value

```rust
use std::mem::MaybeUninit;

let mut slot = MaybeUninit::<u32>::uninit();
slot.write(42);

// SAFETY: `write` initialized a valid u32 in the slot.
let value = unsafe { slot.assume_init() };
assert_eq!(value, 42);
```

## Good: Element-by-Element Array Initialization

```rust
use std::mem::MaybeUninit;

let mut items: [MaybeUninit<u32>; 4] = [const { MaybeUninit::uninit() }; 4];
for (i, item) in items.iter_mut().enumerate() {
    item.write(i as u32);
}

// SAFETY: every array element now contains a valid u32. Padding, if a
// destination type had any, would not need arbitrary byte initialization.
let items = unsafe { MaybeUninit::<[u32; 4]>::from(items).assume_init() };
assert_eq!(items, [0, 1, 2, 3]);
```

## FFI and Partial Initialization

When C or another unsafe producer initializes an object, prove that all fields/parts required by `T`'s validity invariant have been initialized before calling `assume_init`. A function that merely writes some bytes is not enough.

## Key Points

- `MaybeUninit<T>` is the standard representation for memory that may not yet contain a valid `T`.
- `assume_init` requires a valid initialized `T`, not arbitrary initialization of padding bytes.
- Track partial initialization carefully so initialized elements are dropped exactly once on error paths.
- `mem::zeroed()` is sound only for types for which the all-zero bit pattern is valid; prefer APIs that make that invariant explicit.

## See Also

- [unsafe-safety-comment](unsafe-safety-comment.md) — document the proof behind `assume_init`
- [`MaybeUninit`](https://doc.rust-lang.org/stable/std/mem/union.MaybeUninit.html)
