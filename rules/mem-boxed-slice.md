# mem-boxed-slice

> Use `Box<[T]>` when owned heap data has a fixed length and you do not need spare capacity or growth operations

## Why It Matters

`Vec<T>` represents an owned growable sequence and therefore tracks pointer, length, and capacity. `Box<[T]>` represents an owned fixed-length slice and tracks only the fat-pointer metadata needed for the allocation and length. On common 64-bit targets that often means one fewer machine word in the owner value, but portable code should not assume exact byte counts without checking the target.

The stronger reason to choose `Box<[T]>` is semantic: once construction is complete, the type says that changing the number of elements is not part of the API.

## Basic Conversion

```rust
fn freeze(values: Vec<u32>) -> Box<[u32]> {
    values.into_boxed_slice()
}

fn main() {
    let values = freeze(vec![10, 20, 30]);
    assert_eq!(&*values, &[10, 20, 30]);
}
```

`Vec::into_boxed_slice()` discards excess capacity like `shrink_to_fit` before producing the boxed slice. You do **not** need to call `shrink_to_fit()` first.

## Do Not Assume Exact `Vec` Capacity

`Vec::with_capacity(n)` guarantees capacity of **at least** `n`. The standard library guarantees that it requests allocation space for exactly `n` elements, but the allocator may return a larger allocation and `Vec::capacity()` is allowed to exceed the request. Zero-sized element types are a special case as well.

```rust
fn main() {
    let values = Vec::<u8>::with_capacity(128);
    assert!(values.capacity() >= 128);
}
```

Do not teach `Vec::with_capacity(n).capacity() == n` as a language or library guarantee.

## Layout Is Target-Dependent

```rust
use std::mem::size_of;

fn main() {
    assert!(size_of::<Box<[u8]>>() <= size_of::<Vec<u8>>());
}
```

On ordinary 64-bit targets, `Vec<T>` is commonly three words and `Box<[T]>` two words, but pointer width and ABI matter. If the exact owner size is important, measure the targets you support rather than hard-coding a portable assertion such as `24` or `16` bytes.

The allocation containing the elements is separate from this owner metadata; converting to `Box<[T]>` does not somehow compress the elements themselves.

## Construct Once, Then Freeze

A common pattern is to use `Vec<T>` while building and convert at the storage boundary:

```rust
fn squares(count: u32) -> Box<[u32]> {
    let mut values = Vec::with_capacity(count as usize);
    for value in 0..count {
        values.push(value * value);
    }
    values.into_boxed_slice()
}

fn main() {
    assert_eq!(&*squares(4), &[0, 1, 4, 9]);
}
```

This keeps convenient growable construction while exposing a fixed-length representation afterward.

## Fixed Length Does Not Mean Immutable Elements

`Box<[T]>` prevents changing the slice length, not changing elements:

```rust
fn main() {
    let mut values: Box<[u32]> = vec![1, 2, 3].into_boxed_slice();
    values[1] = 20;
    assert_eq!(&*values, &[1, 20, 3]);
}
```

If the elements themselves must not be mutated, enforce that through ownership/borrowing/API design rather than assuming the boxed slice type does it.

## Converting Back to `Vec`

If requirements change and the collection must grow again, conversion back is supported:

```rust
fn append(mut values: Box<[u32]>, value: u32) -> Vec<u32> {
    let mut values = values.into_vec();
    values.push(value);
    values
}

fn main() {
    let boxed = vec![1, 2].into_boxed_slice();
    assert_eq!(append(boxed, 3), vec![1, 2, 3]);
}
```

Whether growth reallocates depends on the capacity of the resulting vector and implementation details. If repeated length changes are normal, keep a `Vec<T>` instead of repeatedly switching representations.

## Avoid Clone-and-Round-Trip Mutation

Do not clone a boxed slice into a vector just to perform ordinary repeated growth:

```rust
fn with_extra(values: &[u32], extra: u32) -> Box<[u32]> {
    let mut result = Vec::with_capacity(values.len() + 1);
    result.extend_from_slice(values);
    result.push(extra);
    result.into_boxed_slice()
}

fn main() {
    assert_eq!(&*with_extra(&[1, 2], 3), &[1, 2, 3]);
}
```

This is reasonable when you intentionally create a new fixed sequence. If the same owned collection is modified repeatedly, `Vec<T>` better expresses the workload.

## `Box<str>` Uses the Same Fixed-Size Idea

For an owned string that will not grow, `Box<str>` removes spare-capacity semantics from the owner:

```rust
fn normalize(name: String) -> Box<str> {
    name.trim().to_owned().into_boxed_str()
}

fn main() {
    assert_eq!(&*normalize(" Ada ".to_owned()), "Ada");
}
```

As with `Box<[T]>`, exact metadata-size savings are target-dependent. `Box<str>` also still owns a heap allocation; small-string optimized representations may be better when allocation count is the real issue.

## When to Use What

| Type | Good fit |
|---|---|
| `Vec<T>` | owned sequence that may grow/shrink or benefits from spare capacity |
| `Box<[T]>` | owned fixed-length heap sequence |
| `[T; N]` | fixed length known in the type, with inline storage wherever the value lives |
| `&[T]` | borrowed view; no ownership needed |
| `Arc<[T]>` | fixed-length owned data shared across threads/owners |

Do not describe `[T; N]` as necessarily “stack allocated”: arrays are stored inline in their containing value, which itself may live on the stack, heap, static storage, or elsewhere.

## Practical Guidance

- Build with `Vec<T>` when growth is useful, then freeze with `into_boxed_slice()` when the length becomes fixed.
- Do not pre-call `shrink_to_fit()` solely for `into_boxed_slice()`.
- Do not assume `Vec::with_capacity(n)` reports capacity exactly `n`.
- Measure owner layout on supported targets if the metadata bytes matter.
- Keep `Vec<T>` when repeated growth/shrink is part of normal use.
- Use the fixed-length type mainly because it matches semantics; memory savings are workload- and target-dependent.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) - Reserving vector capacity
- [mem-arc-str](./mem-arc-str.md) - Shared fixed strings
- [own-slice-over-vec](./own-slice-over-vec.md) - Borrowed slice APIs
- [mem-compact-string](./mem-compact-string.md) - Small/compact owned strings
