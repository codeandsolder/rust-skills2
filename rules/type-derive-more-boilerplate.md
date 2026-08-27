# type-derive-more-boilerplate

> Use `derive_more` to remove mechanical trait boilerplate when the generated trait semantics are actually part of your API

**Rule**: `type-derive-more-boilerplate`

## Why It Matters

Newtypes often need straightforward implementations of traits such as `From`, `Display`, `AsRef`, `Deref`, `FromStr`, or `IntoIterator`. `derive_more` can generate those implementations, but each derive changes the public capabilities of the type.

Do not treat “derive everything the inner type has” as automatically good newtype design. A validated/domain type may deliberately **not** expose `Deref`, arbitrary `From`, arithmetic operators, or mutable iteration because those traits can bypass or obscure its abstraction boundary.

The examples here follow current `derive_more` 2.1.x behavior.

## Simple Transparent Formatting and Construction

For a single-field newtype, `From` wraps the field type and `Display` can transparently delegate to it:

```rust
use derive_more::{Display, From};

#[derive(Debug, Clone, PartialEq, Eq, From, Display)]
struct Username(String);

fn main() {
    let name = Username::from("alice".to_owned());
    assert_eq!(name.to_string(), "alice");
}
```

This is a good fit when **every** `String` is a valid `Username`. If construction must validate an invariant, do not derive an unconditional `From<String>` just to save boilerplate; provide a checked constructor/`TryFrom` instead.

## `AsRef` Default vs Forwarding

Current `derive_more` does **not** make a `String` newtype implement `AsRef<str>` merely from bare `#[derive(AsRef)]`. The default exposes the field type itself:

```rust
use derive_more::AsRef;

#[derive(AsRef)]
struct Wrapped(String);

fn main() {
    let wrapped = Wrapped("hello".to_owned());
    let string: &String = wrapped.as_ref();
    assert_eq!(string, "hello");
}
```

When the public API should expose a specific borrowed target, request it explicitly:

```rust
use derive_more::AsRef;

#[derive(AsRef)]
#[as_ref(str)]
struct Name(String);

fn main() {
    let name = Name("Ada".to_owned());
    let text: &str = name.as_ref();
    assert_eq!(text, "Ada");
}
```

`#[as_ref(forward)]` is broader: it forwards the field's compatible `AsRef<T>` implementations. Use that only when exposing all of those conversions is intended.

## `Deref` Default vs Forwarding

Bare `#[derive(Deref)]` dereferences to the **field type**. For `struct Name(String)`, that means `Target = String`, not `str`:

```rust
use derive_more::Deref;

#[derive(Deref)]
struct Name(String);

fn main() {
    let name = Name("Ada".to_owned());
    let string: &String = &name;
    assert_eq!(string.len(), 3);
}
```

If you intentionally want to forward the wrapped type's own dereference operation, use `#[deref(forward)]`:

```rust
use derive_more::Deref;

#[derive(Deref)]
#[deref(forward)]
struct Name(String);

fn main() {
    let name = Name("Ada".to_owned());
    let text: &str = &name;
    assert_eq!(text, "Ada");
}
```

For many domain newtypes, an explicit `as_str()`/`as_slice()` method is a better API than `Deref`, because it does not automatically expose the wrapped type's method surface and coercions.

## `FromStr` Forwards Parsing of the Inner Type

For a newtype, `FromStr` works when the wrapped type itself implements `FromStr`; the generated implementation parses the inner value and wraps it. Its error behavior follows that inner parse unless you configure a custom error.

```rust
use derive_more::FromStr;

#[derive(Debug, PartialEq, Eq, FromStr)]
struct Port(u16);

fn main() -> Result<(), std::num::ParseIntError> {
    let port: Port = "8080".parse()?;
    assert_eq!(port.0, 8080);
    Ok(())
}
```

For `String`, parsing is infallible; do not document a generic invented `ParseError` as though every derived `FromStr` uses one.

If parsing a domain type requires validation beyond the inner type's parser, write or configure the conversion that enforces that invariant.

## `IntoIterator` Defaults to Owned Iteration

For a single-field collection wrapper, bare `IntoIterator` derives the owned implementation:

```rust
use derive_more::IntoIterator;

#[derive(IntoIterator)]
struct Numbers(Vec<i32>);

fn main() {
    let sum: i32 = Numbers(vec![1, 2, 3]).into_iter().sum();
    assert_eq!(sum, 6);
}
```

If the wrapper should also support iteration through `&Wrapper` or `&mut Wrapper`, request those implementations explicitly with the derive's `owned`, `ref`, and `ref_mut` options rather than assuming they are generated automatically.

```rust
use derive_more::IntoIterator;

#[derive(IntoIterator)]
#[into_iterator(owned, ref, ref_mut)]
struct Numbers(Vec<i32>);

fn main() {
    let mut numbers = Numbers(vec![1, 2, 3]);
    assert_eq!((&numbers).into_iter().copied().sum::<i32>(), 6);
    for value in &mut numbers {
        *value *= 2;
    }
    assert_eq!(numbers.into_iter().collect::<Vec<_>>(), [2, 4, 6]);
}
```

## Numeric Operators Should Match Domain Semantics

Operator derives are convenient for unit-like numeric wrappers, but only derive operations that make sense:

```rust
use derive_more::{Add, AddAssign, Display, From};

#[derive(Debug, Clone, Copy, PartialEq, From, Add, AddAssign, Display)]
struct Meters(f64);

fn main() {
    let mut distance = Meters(10.0);
    distance += Meters(2.5);
    assert_eq!(distance, Meters(12.5));
    assert_eq!(distance.to_string(), "12.5");
}
```

Do not mechanically derive multiplication of `Meters * Meters -> Meters` merely because the inner `f64` supports multiplication; the domain result would normally have different units.

## A Correct Combined Newtype Example

```rust
use derive_more::{AsRef, Display, From, FromStr};

#[derive(Debug, Clone, PartialEq, Eq, Hash, From, AsRef, Display, FromStr)]
#[as_ref(str)]
struct Username(String);

fn main() {
    let name = Username::from("alice".to_owned());

    assert_eq!(name.to_string(), "alice");
    let borrowed: &str = name.as_ref();
    assert_eq!(borrowed, "alice");

    let parsed: Username = "bob".parse().expect("String parsing is infallible");
    assert_eq!(parsed.to_string(), "bob");

    // `name` remains usable: none of the examples above moved its field out.
    assert_eq!(name.to_string(), "alice");
}
```

The previous version moved `name.0` into a `String` and then continued using `name`, which was a genuine ownership error rather than a harmless standalone-snippet artifact.

## Feature Selection

`derive_more` 2.x exposes derives behind crate features. Enable only the features you use, or use the crate's `full` feature when that trade-off is acceptable:

```toml
[dependencies]
derive_more = { version = "2", features = ["from", "display", "as_ref", "from_str", "into_iterator"] }
```

Check the current crate documentation when adding a derive: macro syntax and forwarding options are crate-version-specific APIs.

## When Manual Implementations Are Better

Prefer a manual trait implementation when:

- conversion must validate invariants;
- error mapping is part of your public API;
- formatting differs from the inner value;
- dereference/borrow exposure should be narrower than the wrapped type;
- operator semantics need units, saturation, checking, or another domain rule;
- generated trait bounds would over-constrain generic code;
- the explicit implementation is clearer than derive attributes.

Boilerplate reduction is useful only when the generated semantics are the semantics you actually want.

## Practical Guidance

- Derive mechanical traits only after deciding that each trait belongs in the type's API.
- Remember that bare `AsRef` and `Deref` target the wrapped field; forwarding is explicit.
- Use `#[as_ref(str)]` or `#[as_ref(forward)]` deliberately rather than assuming `String -> str` forwarding.
- Use `#[deref(forward)]` only when forwarding the inner dereference is intentional.
- Treat `FromStr` errors as inner-parser/configuration dependent, not one universal `ParseError`.
- Request reference forms of `IntoIterator` explicitly when needed.
- Keep validation and domain semantics ahead of boilerplate reduction.

## See Also

- [type-newtype-ids](./type-newtype-ids.md) - ID newtypes
- [type-newtype-validated](./type-newtype-validated.md) - Validated newtypes
- [type-nutype-validated](./type-nutype-validated.md) - `nutype` for validation-oriented newtypes
- [type-newtype-repr-transparent](./type-newtype-repr-transparent.md) - Representation transparency
- [derive_more docs](https://docs.rs/derive_more/latest/derive_more/) - Current derive syntax and behavior
