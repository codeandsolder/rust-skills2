# api-from-not-into

> Implement `From<Source> for Destination` for clear infallible conversions you own; use `Into<Destination>` primarily as a caller-side bound

## Why It Matters

The standard library provides a blanket implementation that makes `From<T> for U` imply `Into<U> for T`. Implementing `From` therefore gives callers both spellings:

- `U::from(value)` when the destination type should be explicit;
- `value.into()` when context already determines the destination.

This is why the standard library recommends implementing `From` rather than `Into` directly in modern Rust.

## Good: Implement `From` Once

```rust
#[derive(Debug, PartialEq, Eq)]
struct UserId(u64);

impl From<u64> for UserId {
    fn from(value: u64) -> Self {
        Self(value)
    }
}

fn main() {
    assert_eq!(UserId::from(7), UserId(7));

    let via_into: UserId = 9_u64.into();
    assert_eq!(via_into, UserId(9));
}
```

There is no need to add a matching manual `Into<UserId> for u64`; doing so would overlap with the blanket `Into` implementation supplied because `UserId: From<u64>`.

## Use `Into` as an Input Bound When Appropriate

Although `From` is the implementation-side default, `Into<T>` is often the more flexible generic **bound** because it also accepts a source type that happens to implement `Into<T>` directly.

```rust
#[derive(Debug, PartialEq, Eq)]
struct Label(String);

impl From<&str> for Label {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}

fn make_label(value: impl Into<Label>) -> Label {
    value.into()
}

fn main() {
    assert_eq!(make_label("ready"), Label("ready".into()));
}
```

Keep the generic bound only when accepting multiple converting source types actually improves the API.

## `From` Is for Infallible, Non-Lossy, Obvious Conversions

The standard docs describe `From` as a conversion that must not fail and should preserve the relevant information/meaning. Do not add `From` merely because a conversion can be written.

For validation or other failure, use `TryFrom`:

```rust
use std::num::NonZeroU32;

fn main() {
    assert_eq!(NonZeroU32::try_from(5_u32).unwrap().get(), 5);
    assert!(NonZeroU32::try_from(0_u32).is_err());
}
```

For domain-dependent or intentionally lossy conversions, a named constructor/method can be clearer than either standard conversion trait.

## The Blanket Relationship Is a Contract, Not Code You Reimplement

Conceptually:

`U: From<T>` → `T: Into<U>`

That implementation lives in the standard library. Do not copy a generic `impl<T, U> Into<U> for T where U: From<T>` into examples or application code; `Into` is a foreign trait and the blanket implementation already exists.

A compileable way to demonstrate the relationship is to use a generic bound:

```rust
#[derive(Debug, PartialEq, Eq)]
struct Wrapper(u32);

impl From<u32> for Wrapper {
    fn from(value: u32) -> Self {
        Self(value)
    }
}

fn accepts_into<T: Into<Wrapper>>(value: T) -> Wrapper {
    value.into()
}

fn main() {
    assert_eq!(accepts_into(12_u32), Wrapper(12));
}
```

## The Old Pre-1.41 Orphan-Rule Exception Is Historical

Older Rust versions could have situations where converting into an external destination allowed a direct `Into` impl but not the corresponding `From` impl. Rust 1.41 relaxed the orphan rules, enabling the important local-type cases that motivated that workaround.

For current Rust, do not teach “external destination type” as a normal reason to implement `Into` directly. Apply today's coherence rules to the concrete impl you want.

For example, this modern `From` impl is legal because `Local<T>` is a local type participating in the foreign-trait impl:

```rust
struct Local<T>(Vec<T>);

impl<T> From<Local<T>> for Vec<T> {
    fn from(value: Local<T>) -> Self {
        value.0
    }
}

fn main() {
    let values: Vec<_> = Local(vec![1, 2, 3]).into();
    assert_eq!(values, vec![1, 2, 3]);
}
```

Coherence depends on the actual local/foreign types and uncovered type parameters; a diagnostic attribute or style preference cannot override those rules.

## Direct `Into` Implementations Are Rarely the Starting Point

A manual `Into` impl can exist only when it is coherent and does not overlap another implementation. But it has two disadvantages compared with a corresponding legal `From` impl:

- it does not automatically provide `From` in the reverse trait direction;
- it is less idiomatic and can become incompatible if a `From` impl is later added (because that would generate a blanket `Into`).

Start with `From` whenever the conversion meets `From`'s semantic contract and coherence permits it.

## Fallible Counterpart

`TryFrom<T> for U` similarly gives `TryInto<U> for T` through a standard blanket implementation.

```rust
#[derive(Debug, PartialEq, Eq)]
struct Port(u16);

impl TryFrom<u32> for Port {
    type Error = &'static str;

    fn try_from(value: u32) -> Result<Self, Self::Error> {
        u16::try_from(value)
            .map(Port)
            .map_err(|_| "port is out of range")
    }
}

fn main() {
    let port: Port = 443_u32.try_into().unwrap();
    assert_eq!(port, Port(443));
    assert!(Port::try_from(70_000_u32).is_err());
}
```

Use the same design discipline: conversion traits should represent stable, unsurprising relationships between types.

## Practical Guidance

- Implement `From<T> for U` rather than `Into<U> for T` when the `From` impl is legal and semantically appropriate.
- Use `Into<U>` as a generic input bound when accepting all converting source types is useful.
- Do not manually reproduce std's blanket `Into` implementation.
- Treat pre-Rust-1.41 orphan-rule advice as history, not a current design pattern.
- Use `TryFrom`/`TryInto` for conversions that can fail.
- Prefer named methods for conversions whose lossiness or domain meaning deserves an explicit verb.

## See Also

- [api-impl-into](./api-impl-into.md) - Generic ownership-taking parameters
- [api-impl-asref](./api-impl-asref.md) - Cheap borrowed views
- [err-from-impl](./err-from-impl.md) - Error conversion with `From`
- [api-newtype-safety](./api-newtype-safety.md) - Newtype conversion design
