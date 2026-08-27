# mem-box-large-variant

> Consider indirection when one enum variant makes every enum value much larger, but measure the workload before paying for a heap allocation

## Why It Matters

An enum must be large enough and sufficiently aligned for any of its variants. A rarely used large payload can therefore increase the inline size of **every** value of that enum. Boxing that payload replaces the inline data with a pointer-sized field and can improve density in arrays, vectors, queues, and caches.

That trade is not free. `Box<T>` adds an allocation, pointer chasing, allocator metadata/traffic, and another failure boundary at allocation time. If the large variant is common, short-lived, or already behind indirection, boxing can make the program slower while saving little useful memory.

Treat `large_enum_variant` as a profiling/layout prompt, not as a command.

## Compare the Layout You Actually Have

```rust
use std::mem::size_of;

struct ImageData {
    data: [u8; 1024],
    width: u32,
    height: u32,
}

enum InlineMessage {
    Quit,
    Move { x: i32, y: i32 },
    Text(String),
    Image(ImageData),
}

enum BoxedMessage {
    Quit,
    Move { x: i32, y: i32 },
    Text(String),
    Image(Box<ImageData>),
}

fn main() {
    assert!(size_of::<BoxedMessage>() < size_of::<InlineMessage>());
}
```

Do not hard-code the exact byte counts in portable guidance. Enum layout depends on target pointer width, alignment, niche opportunities, payload types, and representation attributes.

## Density Can Matter More Than One Isolated Value

If a collection contains many values, reducing the enum's inline size can reduce the collection's resident footprint and increase the number of elements that fit in a cache line:

```rust
use std::mem::size_of;

struct Large([u8; 512]);

enum Inline {
    Small(u32),
    Large(Large),
}

enum Indirect {
    Small(u32),
    Large(Box<Large>),
}

fn bytes_for<T>(count: usize) -> usize {
    size_of::<T>() * count
}

fn main() {
    assert!(bytes_for::<Indirect>(10_000) < bytes_for::<Inline>(10_000));
}
```

This only measures the **inline container storage**. The boxed form also has heap allocations for values that use the large variant, so total memory depends on the variant distribution and allocator.

## Clippy's `large_enum_variant` Is Deliberately Heuristic

```toml
[lints.clippy]
large_enum_variant = "warn"
result_large_err = "warn"
```

Clippy's `large_enum_variant` compares variant sizes and can suggest boxing. Its threshold is configurable (`enum-variant-size-threshold`; currently 200 bytes by default), but Clippy explicitly cannot know the runtime frequency of each variant. A suggestion can therefore be counterproductive when the supposedly large variant dominates the workload.

`result_large_err` is similar: a large error type can make every `Result<T, E>` wider. Consider boxing or otherwise slimming the error representation when measurements/layout inspection justify it; do not mechanically box every rich error enum.

## No Universal Byte Threshold

Rules such as “box anything above 128 bytes” or “always box above 256 bytes” are too crude. Relevant factors include:

- how often each variant occurs;
- whether values live in dense collections;
- allocation frequency and allocator cost;
- locality and pointer-chasing sensitivity;
- whether the type needs `Copy`;
- target ABI/layout;
- whether an arena, side table, ID/handle, or shared allocation better matches ownership.

Use `size_of::<T>()`, Clippy, heap/allocation profiling, and workload benchmarks together.

## Recursive Types Are a Different Reason for Indirection

A directly recursive type has no finite size, so some form of indirection is required. This is a type-system requirement, not the same optimization decision as boxing a merely large variant.

```rust
#[derive(Debug, PartialEq)]
enum List {
    Cons(i32, Box<List>),
    Nil,
}

fn main() {
    let list = List::Cons(1, Box::new(List::Cons(2, Box::new(List::Nil))));
    assert!(matches!(list, List::Cons(1, _)));
}
```

Recursive structures do not necessarily require `Box` specifically. `Rc`, `Arc`, arena indices, IDs, or other indirection can be more appropriate depending on sharing and lifetime requirements.

## Pattern Matching Remains Straightforward

```rust
struct LargeData {
    size: usize,
}

enum Event {
    Small(u32),
    Large(Box<LargeData>),
}

fn describe(event: &Event) -> usize {
    match event {
        Event::Small(value) => *value as usize,
        Event::Large(data) => data.size,
    }
}

fn main() {
    let event = Event::Large(Box::new(LargeData { size: 4096 }));
    assert_eq!(describe(&event), 4096);
}
```

Deref coercions make ordinary field/method access through `Box<T>` convenient; there is usually no need to write explicit `*` operations just to read fields.

## Alternatives to Per-Value Boxing

If allocation overhead is the problem, consider whether the large payload belongs somewhere else:

- an arena with handles/indices;
- a side table keyed by an ID;
- `Arc<T>` when large payloads are shared;
- splitting hot and cold fields into separate structures;
- a different enum/data model that reflects actual variant frequencies.

These alternatives change ownership and lifetime semantics, so use them only when they fit the design.

## Practical Guidance

- Inspect the actual enum size on supported targets.
- Pay attention to variant frequency, not just maximum payload size.
- Box a large/cold variant when denser inline storage is worth the allocation and indirection.
- Do not turn Clippy's heuristic threshold into a universal design rule.
- Keep recursive-type indirection conceptually separate from large-variant optimization.
- Benchmark the representative collection/workload after changing representation.

## See Also

- [own-move-large](./own-move-large.md) - Large values and move costs
- [mem-arena-allocator](./mem-arena-allocator.md) - Arena allocation for shared lifetimes
- [mem-slotmap-arena](./mem-slotmap-arena.md) - Stable handles and side storage
- [perf-profile-first](./perf-profile-first.md) - Measure before optimizing
