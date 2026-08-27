# mem-thinvec

> Use `ThinVec<T>` when a pointer-sized collection handle is valuable

## Why It Matters

`ThinVec<T>` from Mozilla's `thin_vec` crate stores length and capacity in the allocation rather than in the collection value itself. The collection handle is pointer-sized, and the crate guarantees that `ThinVec<T>` and `Option<ThinVec<T>>` have the same size.

That can reduce the size of structs containing many vector fields or large arrays/vectors of collection handles. The trade-off is that accessing length/capacity for a non-empty value involves the allocation header, and every non-zero-capacity `ThinVec` needs that header allocation.

An empty `ThinVec::new()` does **not** use a null pointer. It performs no heap allocation and points at a statically allocated empty header. Avoid inferring representation details beyond the crate's documented guarantees.

As of August 2026, the current release is `thin-vec` 0.2.18.

## Bad

<!-- rust-check: compile -->
```rust
struct Metadata;

struct SparseData {
    // Each Vec value carries its pointer/length/capacity handle even when empty.
    tags: Vec<String>,
    metadata: Vec<Metadata>,
}

struct TreeNode {
    value: i32,
    children: Vec<TreeNode>,
}
```

There is nothing incorrect about `Vec` here. Switch representations only when the size of the collection handle matters enough to justify the different trade-offs.

## Good

<!-- rust-check: compile -->
```rust
use thin_vec::ThinVec;

struct Metadata;

struct SparseData {
    tags: ThinVec<String>,
    metadata: ThinVec<Metadata>,
}

struct TreeNode {
    value: i32,
    children: ThinVec<TreeNode>,
}

let empty: ThinVec<u8> = ThinVec::new();
assert!(empty.is_empty());
```

## Documented Layout Property

```rust
use std::mem::size_of;
use thin_vec::ThinVec;

assert_eq!(size_of::<ThinVec<u8>>(), size_of::<*const u8>());
assert_eq!(size_of::<Option<ThinVec<u8>>>(), size_of::<ThinVec<u8>>());
```

Use pointer-relative assertions like these if layout matters. Hard-coding “8 bytes” or “24 bytes” makes examples accidentally target-specific.

## Empty and Non-Empty Values

```rust
use thin_vec::ThinVec;

let empty = ThinVec::<u32>::new();
assert_eq!(empty.len(), 0);
assert_eq!(empty.capacity(), 0);

let mut values = ThinVec::with_capacity(4);
values.extend([1, 2, 3]);
assert!(values.capacity() >= 4);
assert_eq!(&values[..], &[1, 2, 3]);
```

`ThinVec::new()` uses a shared static empty header and does not allocate. A requested non-zero capacity requires an allocation because the allocation carries the length/capacity header.

## ThinVec vs Vec

| Property | `Vec<T>` | `ThinVec<T>` |
|----------|----------|--------------|
| Collection handle | Three-word design | Pointer-sized |
| Empty construction | No heap allocation | No heap allocation; static empty header |
| Length/capacity | Stored in value | Stored in allocation header |
| `Option` size | Target/layout dependent niche behavior | Documented same size as `ThinVec<T>` |
| Raw-parts / Box round-trip | Rich standard-library support | More restricted |

Do not claim that one representation is universally faster. Whether the smaller handle outweighs the extra indirection depends on access patterns, allocator behavior, target, and surrounding data layout.

## API Compatibility

```rust
use thin_vec::{thin_vec, ThinVec};

let mut v: ThinVec<i32> = thin_vec![1, 2, 3];
v.push(4);
v.extend([5, 6]);
assert_eq!(v.pop(), Some(6));

for item in &v {
    assert!(*item > 0);
}

let slice: &[i32] = &v[..];
assert_eq!(slice, &[1, 2, 3, 4, 5]);

let vec: Vec<i32> = v.into();
let thin: ThinVec<i32> = vec.into();
assert_eq!(&thin[..], &[1, 2, 3, 4, 5]);
```

## When to Use It

Consider `ThinVec` when:
- many collection handles are stored and their inline footprint matters;
- most values are empty or small enough that handle density matters;
- profiling or layout inspection shows that reducing parent-object size is useful.

Prefer `Vec` when its standard-library guarantees, raw-parts interoperability, or simpler hot-path access are more important.

## Cargo.toml

```toml
[dependencies]
thin-vec = "0.2.18"
```

## See Also

- [mem-smallvec](./mem-smallvec.md) - Inline storage for usually-small vectors
- [mem-boxed-slice](./mem-boxed-slice.md) - Fixed-size heap slices
- [mem-slotmap-arena](./mem-slotmap-arena.md) - Stable handles with contiguous storage
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocation strategies
