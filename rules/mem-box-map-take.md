# mem-box-map-take

> Use Rust 1.100 `Box::map` and `Box::take` for value transformations that can preserve heap allocation

**Rule**: `mem-box-map-take`

## Why It Matters

Replacing `Box<T>` with `Box<U>` using `Box::new(f(*boxed))` requires another box allocation. Rust 1.100 stabilizes `Box::map`, which consumes the original box and can reuse its allocation when layout permits. `Box::take` extracts the owned value and returns a `Box<MaybeUninit<T>>` to the allocation so it can be reinitialized safely.

Avoid assuming that reuse is unconditional: the optimizer and allocator may need to allocate again for a changed size or alignment.

## Good: Transform While Retaining Owned Representation

```rust
fn main() {
    let number = Box::new(7_u32);
    let doubled = Box::map(number, |number| number * 2);
    assert_eq!(*doubled, 14);

    let (old, spare) = Box::take(doubled);
    assert_eq!(old, 14);
    let new = Box::write(spare, 99);
    assert_eq!(*new, 99);
}
```

The type of the second `Box::take` return value is intentionally **uninitialized**. Never dereference it as `T` before successfully writing a valid value. This is not a mechanism for accessing a value twice.

Rust 1.100 also stabilizes `Rc::map` and `Arc::map`. Review their ownership/shared-count semantics separately rather than treating them as identical to an exclusive `Box`.

## See Also

- [mem-box-new-uninit](./mem-box-new-uninit.md) — safe initialization of boxed storage
- [mem-custom-allocator](./mem-custom-allocator.md) — allocator-parametric boxes
- [own-arc-shared](./own-arc-shared.md) — shared ownership costs
