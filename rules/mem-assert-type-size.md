# mem-assert-type-size

> Assert type size when it is a real ABI, memory-budget, or measured performance constraint; prefer upper bounds when exact layout is not required

## Why It Matters

A type stored millions of times can become materially more expensive when one field changes its size or alignment. Compile-time size assertions turn that implicit cost into an explicit contract reviewed with the code change.

But `size_of::<T>() == N` is a strong promise. It is appropriate when exact size is genuinely required—for example an FFI/wire layout with an explicitly chosen representation. For ordinary Rust data structures, a maximum-size assertion is often better: it catches a memory regression without pretending that every field offset or ABI detail is stable.

Size is target-dependent. Pointer width, alignment, enum layout, and dependency types can differ across targets, so assert on the targets where the contract actually matters.

## Bad: Accidental Exact-Layout Folklore

```rust
struct CacheEntry {
    key: u64,
    value: String,
}

fn main() {
    // BAD as a portable API promise: the exact size depends on the target and
    // on the representation of fields such as String.
    assert_eq!(std::mem::size_of::<CacheEntry>(), 32);
}
```

A runtime test is also easy to skip and does not prevent building a binary with the undesired layout.

## Good: Compile-Time Memory Budget

```rust
use static_assertions::const_assert;

struct HotRecord {
    timestamp: u64,
    id: u32,
    flags: u16,
    kind: u16,
    payload: [u8; 32],
}

const_assert!(std::mem::size_of::<HotRecord>() <= 48);

fn main() {
    assert!(std::mem::size_of::<HotRecord>() <= 48);
}
```

The upper bound expresses the actual requirement: this frequently stored type must stay within a chosen memory budget. If a field addition pushes it over, compilation fails.

## Good: Exact Size for an Explicit C Layout

```rust
#[repr(C)]
struct Header {
    version: u16,
    flags: u16,
    length: u32,
    checksum: u64,
    reserved: [u8; 16],
}

const _: () = assert!(
    std::mem::size_of::<Header>() == 32,
    "Header layout changed",
);

fn main() {
    assert_eq!(std::mem::size_of::<Header>(), 32);
}
```

`#[repr(C)]` gives the struct C-compatible field-layout rules. The assertion then checks the expected total size on the target being compiled. If this is an external binary ABI, also document and test the target/endianness/alignment assumptions that size alone does not verify.

## Field Order Can Change Padding Under `repr(C)`

```rust
use std::mem::size_of;

#[repr(C)]
struct Wasteful {
    a: u8,
    b: u64,
    c: u8,
}

#[repr(C)]
struct Compact {
    b: u64,
    a: u8,
    c: u8,
}

fn main() {
    assert_eq!(size_of::<Wasteful>(), 24);
    assert_eq!(size_of::<Compact>(), 16);
}
```

The compiler cannot reorder `repr(C)` fields for you. If the field order is not externally fixed, grouping fields by alignment can reduce padding.

With ordinary `repr(Rust)`, do not rely on field order or offsets as an ABI contract. A size assertion can still be useful as a regression guard for a measured target, but it does not turn the layout into a stable public representation.

## Avoid `repr(packed)` as a Memory-Optimization Default

Packing removes alignment padding but can leave fields unaligned. Rust places restrictions on forming references to unaligned packed fields, and some accesses require explicit unaligned loads/stores.

Use `repr(packed)` only when an external representation actually requires it and handle unaligned fields deliberately. For in-memory performance work, ordinary layout plus profiling is usually a better starting point.

## `static_assertions`

```rust
use static_assertions::{assert_eq_size, const_assert};

#[repr(C)]
struct Pair {
    left: u64,
    right: u64,
}

assert_eq_size!(Pair, [u8; 16]);
const_assert!(std::mem::align_of::<Pair>() == 8);

fn main() {
    assert_eq!(std::mem::size_of::<Pair>(), 16);
}
```

Built-in const assertions are sufficient for many cases; the crate is convenient when you want macros such as `assert_eq_size!` or several related static checks.

## Do Not Mix Unrelated Allocation Claims Into a Size Rule

`Vec::with_capacity(n)` guarantees capacity of **at least** `n`; the allocator may provide more. Do not use a type-size rule to claim exact `Vec` capacity behavior or derive allocation counts from it.

If a container's retained capacity is part of a memory budget, measure or query `capacity()` directly rather than assuming it equals the requested amount.

## When an Assertion Is Worth It

Use one when a concrete consequence follows from exceeding the limit:

- millions of instances make a few bytes per value material;
- a cache-line or packed-page budget was established by measurement;
- an FFI or binary layout requires a particular representation;
- an enum/struct size has historically regressed accidentally;
- a public low-level crate intentionally promises a layout property.

Skip exact assertions for incidental sizes that nobody actually depends on. Those create maintenance friction and can break legitimate target/compiler evolution without protecting a real invariant.

## See Also

- [mem-smaller-integers](./mem-smaller-integers.md) — choosing integer widths
- [mem-box-large-variant](./mem-box-large-variant.md) — reducing enum size with indirection
- [opt-cache-friendly](./opt-cache-friendly.md) — measured cache-locality work

## References

- [std::mem::size_of](https://doc.rust-lang.org/std/mem/fn.size_of.html)
- [Rust Reference: type layout](https://doc.rust-lang.org/reference/type-layout.html)
- [Vec capacity documentation](https://doc.rust-lang.org/std/vec/struct.Vec.html#method.with_capacity)
