# unsafe-conjure-zst

> Use Rust 1.100 `mem::conjure_zst` only when constructing an inhabited zero-sized value is proven sound

**Rule**: `unsafe-conjure-zst`

## Why It Matters

Rust 1.100 provides `unsafe fn std::mem::conjure_zst<T>() -> T` for a use case previously expressed with `transmute` or `MaybeUninit::assume_init`. A zero-byte layout does **not** imply that constructing a value is always sound: uninhabited types and zero-sized authority tokens exist. A forged marker may falsely claim a held lock, valid lifetime, or initialized global state.

## Good: Proven Ordinary Zero-Sized Value

```rust
#[derive(Debug, PartialEq)]
struct Empty;

fn main() {
    // SAFETY: Empty is inhabited, has size zero and no external validity invariant.
    let empty: Empty = unsafe { std::mem::conjure_zst() };
    assert_eq!(empty, Empty);
}
```

An ordinary value constructor (`Empty` here) is simpler; `conjure_zst` is for generic abstractions that have no ordinary construction path.

## Mandatory Proof Obligations

- Prove `size_of::<T>() == 0` and that `T` is inhabited, *and* that the value does not encode an unfulfilled invariant.
- Do not invent an uninhabited enum, lock token, interpreter/GIL token, lifetime witness, permission token, or other capability.
- Audit all external contracts of `T`; type size alone is insufficient to justify the `unsafe` call.
- Keep the `SAFETY:` explanation adjacent to the call. Do not replace the unsafe operation with a mysterious `transmute::<(), T>`.

## See Also

- [unsafe-safety-comment](./unsafe-safety-comment.md) — explicit invariants
- [type-phantom-marker](./type-phantom-marker.md) — marker semantics
- [unsafe-maybeuninit](./unsafe-maybeuninit.md) — initialization guarantees
