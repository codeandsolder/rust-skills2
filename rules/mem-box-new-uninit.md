# mem-box-new-uninit

> Use `Box::new_uninit()` when you genuinely need deferred or in-place heap initialization; call `assume_init()` only after the allocation contains a valid `T`

**Rule**: `mem-box-new-uninit`

## Why It Matters

`Box::<T>::new_uninit()` (stable since Rust 1.82) allocates space for `T` without first creating a valid `T`. This is useful when an initializer naturally writes into an output pointer, when constructing a very large value field-by-field, or when an FFI routine guarantees that it initializes the entire object.

It is **not** a general-purpose replacement for `Box::new`. Modern Rust can often optimize ordinary construction well, and uninitialized construction moves correctness obligations into `unsafe` code.

## Bad: Assume Initialization After Only a Partial Write

```rust
use std::mem::MaybeUninit;

fn wrong(mut slot: Box<MaybeUninit<[u8; 4096]>>) -> Box<[u8; 4096]> {
    // Imagine an OS/FFI read initialized only the first `n` bytes here.
    let _n = 128usize;

    // BAD: 128 initialized bytes do not make a valid [u8; 4096].
    unsafe { slot.assume_init() }
}
```

A length returned by `read(2)` or a similar API proves only that the reported prefix was written. It does **not** justify converting the entire buffer to an initialized array or slice.

## Good: Initialize Every Field Before `assume_init`

```rust
use std::ptr;

#[derive(Debug, PartialEq)]
struct Packet {
    header: [u8; 64],
    payload: [u8; 4096],
}

fn create_packet() -> Box<Packet> {
    let mut slot = Box::<Packet>::new_uninit();
    let raw = slot.as_mut_ptr();

    unsafe {
        // SAFETY: `raw` points to allocated, properly aligned storage for Packet.
        // We write both fields without first creating references to an
        // uninitialized Packet.
        ptr::addr_of_mut!((*raw).header).write([1u8; 64]);
        ptr::addr_of_mut!((*raw).payload).write([2u8; 4096]);

        // SAFETY: every field now contains a valid value, so the allocation
        // contains a valid Packet.
        slot.assume_init()
    }
}

fn main() {
    let packet = create_packet();
    assert_eq!(packet.header[0], 1);
    assert_eq!(packet.payload[0], 2);
}
```

Do not write `slot.header` or call `assume_init_mut()` merely to initialize fields: the box contains `MaybeUninit<Packet>`, not a valid `Packet`, so creating a reference to the uninitialized `Packet` first would be invalid. Use raw field pointers or initialize a complete value.

## Prefer `Box::write` When You Already Have a Complete Value

`Box::write` (stable since Rust 1.87) safely writes a complete value into a `Box<MaybeUninit<T>>` and returns `Box<T>`:

```rust
fn make_table() -> Box<[usize; 1024]> {
    let slot = Box::<[usize; 1024]>::new_uninit();
    let mut table = [0usize; 1024];

    for (i, value) in table.iter_mut().enumerate() {
        *value = i;
    }

    Box::write(slot, table)
}

fn main() {
    let table = make_table();
    assert_eq!(table[123], 123);
}
```

This avoids a manual `unsafe` conversion and gives the optimizer an opportunity to construct the value directly in the destination.

## Uninitialized Boxed Slices

For a runtime-sized collection whose elements can be initialized one-by-one, use `Box::<[T]>::new_uninit_slice` and write every element before converting the slice:

```rust
fn squares(len: usize) -> Box<[u32]> {
    let mut values = Box::<[u32]>::new_uninit_slice(len);

    for (i, slot) in values.iter_mut().enumerate() {
        slot.write((i * i) as u32);
    }

    // SAFETY: the loop initialized every element.
    unsafe { values.assume_init() }
}

fn main() {
    assert_eq!(&*squares(4), &[0, 1, 4, 9]);
}
```

If only a prefix is initialized, keep the remainder as `MaybeUninit<T>` or use a container/API designed to track initialized length. Do not call `assume_init()` on the whole allocation.

## Fallible Field-by-Field Initialization

`Box<MaybeUninit<T>>` does not know which fields of `T` have been initialized. If construction can fail after initializing a field with a destructor, dropping the box frees the allocation but does **not** automatically run destructors for those manually initialized fields.

For nontrivial fallible construction, either:

- initialize a complete `T` using ordinary safe code and then move/write it into the box;
- track initialization state and explicitly drop already-initialized fields on error; or
- use a higher-level abstraction whose API tracks initialized elements.

The field-by-field technique is easiest to justify for plain data or APIs with an all-or-nothing initialization contract.

## FFI and Output Buffers

An FFI call justifies `assume_init()` only if its contract guarantees that it writes a complete valid `T` on the success path. A function that returns a byte count usually guarantees much less.

For byte-oriented reads where only a prefix becomes initialized, prefer an API that tracks length (for example a `Vec`-based spare-capacity pattern) rather than pretending the entire fixed-capacity buffer became initialized.

## Performance Guidance

Do not attach fixed speedups such as “10× faster” or size thresholds such as “use this above 1 KiB.” Allocation cost, zeroing, copy elision, cache behavior, and the initializer itself vary by allocator, target, optimization level, and workload.

Use `new_uninit` because the initialization contract calls for it or because measurement shows ordinary construction performs avoidable work—not merely because `T` is large.

## Safety Notes

`assume_init()` requires that the stored value be in a state valid for `T`. That does **not** mean every padding byte must have been written, but every field and every byte that participates in `T`'s validity must be initialized appropriately.

Creating references to an uninitialized `T` in order to initialize it is also invalid. Keep access through `MaybeUninit<T>` and raw pointers until the value is valid.

## See Also

- [unsafe-maybeuninit](unsafe-maybeuninit.md) — initialization and validity rules
- [mem-box-large-variant](mem-box-large-variant.md) — boxing large enum variants
- [mem-arena-allocator](mem-arena-allocator.md) — arena allocators for batch allocations

## References

- [std::boxed::Box](https://doc.rust-lang.org/std/boxed/struct.Box.html)
- [std::mem::MaybeUninit](https://doc.rust-lang.org/std/mem/union.MaybeUninit.html)
