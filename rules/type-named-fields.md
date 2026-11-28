# type-named-fields

> Name domain-record fields and distinct semantic values; use tuples for small local structural groupings or genuine newtypes

## Why It Matters

A tuple of several values with the same representation makes swaps
compile successfully and obscures units and meaning at the call site.
Named fields express roles; distinct types can additionally enforce them.
Do not replace every two-element structural tuple with a new public type.

## Good: Model a Domain Record

<!-- rust-check: run -->
```rust
struct Width(u32);
struct Height(u32);

struct Dimensions {
    width: Width,
    height: Height,
}

impl Dimensions {
    fn area(&self) -> u64 {
        u64::from(self.width.0) * u64::from(self.height.0)
    }
}

fn main() {
    let dimensions = Dimensions { width: Width(1920), height: Height(1080) };
    assert_eq!(dimensions.area(), 2_073_600);
}
```

The named record clarifies the roles. The newtypes are warranted if
the application benefits from preventing width/height swaps across
interfaces; otherwise named integer fields alone may suffice.

## Tuples Still Have a Place

Use local pairs, iterator items, destructuring, and standard structural
operations where meaning is immediate from the surrounding expression
(e.g. `enumerate`, `zip`, or `split_at`). A one-field tuple struct is
a natural newtype. For a durable API returning several logically distinct
values, consider a named result record with documented fields, especially
when the values share a type or have different units.

## See Also

- [type-newtype-ids](./type-newtype-ids.md)
- [type-newtype-validated](./type-newtype-validated.md)
- [type-enum-states](./type-enum-states.md)
- [Google Rust Style Guide](https://google.github.io/styleguide/rustguide.html)
