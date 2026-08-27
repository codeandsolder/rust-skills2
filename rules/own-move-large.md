# own-move-large

> Borrow large values when ownership transfer is unnecessary; use indirection when it solves a real layout, location, or ownership problem—not from a fixed byte threshold

## Why It Matters

A Rust move transfers ownership. For a non-`Copy` local moved out of a place, the old place becomes deinitialized and cannot be used again until reinitialized. That language rule does **not** promise that every move becomes a runtime `memcpy` of the type's full size: optimization, return-value placement, inlining, and ABI details can eliminate or transform physical copies.

Large inline values can still matter. Passing or rearranging them may increase stack usage, register/memory traffic, enum size, or code-generation pressure in a real program. But boxing purely because a type crosses an arbitrary 128/512/4096-byte threshold can make performance worse by adding allocation, pointer indirection, and poorer locality.

Start from ownership semantics; profile when the physical move cost is actually important.

## Prefer Borrowing When Ownership Is Not Needed

```rust
struct Image {
    pixels: [u8; 4096],
}

fn checksum(image: &Image) -> u64 {
    image
        .pixels
        .iter()
        .map(|&byte| u64::from(byte))
        .sum()
}

fn invert(image: &mut Image) {
    for byte in &mut image.pixels {
        *byte = 255 - *byte;
    }
}

fn main() {
    let mut image = Image { pixels: [1; 4096] };
    assert_eq!(checksum(&image), 4096);
    invert(&mut image);
    assert_eq!(image.pixels[0], 254);
}
```

Neither helper needs to take ownership. References communicate that directly and avoid forcing the caller to give the value up.

## Ownership Transfer Can Be the Right API

```rust
#[derive(Debug, PartialEq, Eq)]
struct Buffer {
    bytes: [u8; 2048],
}

fn mark_ready(mut buffer: Buffer) -> Buffer {
    buffer.bytes[0] = 1;
    buffer
}

fn main() {
    let buffer = Buffer { bytes: [0; 2048] };
    let buffer = mark_ready(buffer);
    assert_eq!(buffer.bytes[0], 1);
}
```

This API says the function consumes the old state and returns the new state. Do not reject the design merely because the type is large; the optimizer may avoid materializing intermediate copies, and the ownership model may be exactly what the API needs.

If profiling shows physical relocation is costly, then consider changing representation or API shape with evidence.

## When `Box<T>` Has a Structural Benefit

A `Box<T>` gives the owner a pointer-sized inline handle to a separately allocated `T`. That is useful when you need one of the box's actual properties:

- reduce the inline size of a larger struct or enum;
- put a recursively sized value behind indirection;
- keep the pointee at a stable heap address while the box owner moves;
- transfer ownership of a heap-resident object through APIs cheaply at the representation level;
- avoid a very large stack allocation where heap allocation is preferable.

Example:

```rust
struct LargeTable {
    values: [u64; 1024],
}

enum Message {
    Ping,
    Table(Box<LargeTable>),
}

fn main() {
    let message = Message::Table(Box::new(LargeTable { values: [0; 1024] }));

    match message {
        Message::Table(table) => assert_eq!(table.values[0], 0),
        Message::Ping => unreachable!(),
    }
}
```

Here boxing keeps the large variant's payload out of the enum's inline storage. That is a concrete representation reason, unlike “anything above N bytes should be boxed.”

## Boxing Has Costs Too

```rust
struct InlinePoint {
    x: u64,
    y: u64,
}

struct BoxedPoint {
    point: Box<InlinePoint>,
}

fn main() {
    assert!(std::mem::size_of::<BoxedPoint>() <= std::mem::size_of::<InlinePoint>());
}
```

The smaller owner does not mean the whole design is cheaper. Constructing `BoxedPoint` usually performs a heap allocation, accessing the fields follows a pointer, and separately allocated objects can reduce spatial locality.

For collections, `Vec<LargeT>` stores elements inline in one allocation and can have excellent locality. Replacing it with `Vec<Box<LargeT>>` trades relocation size for one allocation and pointer per element. Measure the workload before making that trade.

## Large Stack Values Are a Separate Concern

A large local array can put substantial data in a thread's stack frame. If stack usage itself is the problem, heap construction/indirection may be appropriate—but that is different from claiming that ownership moves are expensive.

When constructing very large heap values, see `Box::new_uninit` / `Box::write` only if ordinary construction actually creates an undesirable stack temporary or an output-pointer API naturally initializes in place. Those APIs carry their own initialization constraints; they are not generic “large move” fixes.

## Do Not Encode Size Thresholds as Universal Rules

Avoid tables such as:

| Size | Recommendation |
|---|---|
| `< 128 B` | never box |
| `> 512 B` | box |
| `> 4 KiB` | definitely box |

The crossover depends on how values are created, moved, accessed, stored, and optimized, plus allocator and target behavior. A 4 KiB value moved once may be fine; thousands of tiny individually boxed nodes may be disastrous for locality.

Use `size_of::<T>()` to understand representation, then benchmark or profile the operation that matters.

## Prefer Purpose-Specific Rules for Other APIs

Raw `Vec` parts, zeroed allocations, `MaybeUninit` slice helpers, and dangling-pointer lints are not general guidance about moving large values. Keep those topics in unsafe/memory/FFI rules where their invariants can be explained accurately rather than attaching a list of recent APIs to this rule.

## Review Questions

Before changing representation, ask:

- Does this function need ownership, or would `&T` / `&mut T` express the contract better?
- Is the problem stack footprint, enum/struct inline size, physical relocation, cache locality, or something else?
- Will boxing add many allocations or pointer chases?
- Does stable heap location itself matter?
- Is there profiler/benchmark evidence that the current representation is a bottleneck?

Change the design for the actual constraint.

## See Also

- [own-borrow-over-clone](./own-borrow-over-clone.md) — borrow when ownership is unnecessary
- [own-copy-small](./own-copy-small.md) — semantic/cheap `Copy` types
- [mem-box-large-variant](./mem-box-large-variant.md) — using indirection to reduce enum size
- [mem-box-new-uninit](./mem-box-new-uninit.md) — deliberate heap initialization
- [perf-profile-first](./perf-profile-first.md) — measure before optimizing

## References

- [Rust Reference: moved and copied types](https://doc.rust-lang.org/reference/expressions.html#moved-and-copied-types)
- [std::boxed::Box](https://doc.rust-lang.org/std/boxed/struct.Box.html)
