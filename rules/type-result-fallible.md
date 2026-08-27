# type-result-fallible

> Use `Result<T, E>` when an operation can fail with useful error information

**Rule**: `type-result-fallible`

## Why It Matters

`Result<T, E>` makes recoverable failure part of an API's type. Callers can propagate the error with `?`, inspect it, attach context, retry, or deliberately discard it. That is usually better than a sentinel value, an `Option` that erases the reason for failure, or an unconditional panic.

## Good: Preserve the Failure Mode

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DivisionError {
    DivideByZero,
}

fn divide(a: i32, b: i32) -> Result<i32, DivisionError> {
    if b == 0 {
        Err(DivisionError::DivideByZero)
    } else {
        Ok(a / b)
    }
}

fn main() {
    assert_eq!(divide(10, 2), Ok(5));
    assert_eq!(divide(10, 0), Err(DivisionError::DivideByZero));
}
```

Use `Option<T>` instead when absence is the whole story and there is no useful error information to preserve.

## Propagate with `?`

```rust
use std::num::ParseIntError;

fn parse_pair(left: &str, right: &str) -> Result<(u32, u32), ParseIntError> {
    let left = left.parse()?;
    let right = right.parse()?;
    Ok((left, right))
}

fn main() -> Result<(), ParseIntError> {
    assert_eq!(parse_pair("4", "7")?, (4, 7));
    Ok(())
}
```

The `?` operator is still explicit error propagation: the function's return type states what can escape to the caller.

## Transform Results Deliberately

```rust
#[derive(Debug, PartialEq, Eq)]
enum Error {
    Negative,
}

fn double_positive(value: i32) -> Result<i32, Error> {
    Ok(value).and_then(|value| {
        if value >= 0 {
            Ok(value * 2)
        } else {
            Err(Error::Negative)
        }
    })
}

fn main() {
    assert_eq!(double_positive(4), Ok(8));
    assert_eq!(double_positive(-1), Err(Error::Negative));

    let text = double_positive(-1).map_err(|error| format!("{error:?}"));
    assert_eq!(text, Err("Negative".to_owned()));
}
```

Common combinators include `map`, `map_err`, `and_then`, `or_else`, `inspect`, and `inspect_err`. Prefer the form that makes control flow clearer; a `match` is often better than a long combinator chain.

## `Result::flatten` (Rust 1.89+)

`flatten` removes one level from `Result<Result<T, E>, E>`. The inner and outer error types must be the same.

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Error {
    Invalid,
}

fn main() {
    let nested: Result<Result<u32, Error>, Error> = Ok(Ok(42));
    assert_eq!(nested.flatten(), Ok(42));

    let nested: Result<Result<u32, Error>, Error> = Ok(Err(Error::Invalid));
    assert_eq!(nested.flatten(), Err(Error::Invalid));
}
```

It is not a special never-type or infallibility feature. If the two error types differ, convert one of them first or handle the layers explicitly.

## Rust 1.92 `unused_must_use` and Uninhabited Break/Error Types

Rust 1.92 stopped warning for specific unit-success/control-flow shapes whose failure/break type is uninhabited, such as `Result<(), Infallible>` and `ControlFlow<Infallible, ()>`.

```rust
use std::convert::Infallible;
use std::ops::ControlFlow;

fn always_ok() -> Result<(), Infallible> {
    Ok(())
}

fn always_continue() -> ControlFlow<Infallible, ()> {
    ControlFlow::Continue(())
}

fn main() {
    always_ok();
    always_continue();
}
```

Do **not** generalize that release-note change to every `Result<T, Infallible>`. A non-unit successful value can itself be important, and the lint behavior is deliberately more specific.

## `#[diagnostic::do_not_recommend]` (Rust 1.85+)

This attribute is a compiler-diagnostic hint for a **legal trait impl** whose appearance in an error message would mislead users. It does not relax coherence/orphan rules and is not an error-conversion feature.

```rust
trait InternalFormat {}
trait PublicFormat {}

#[diagnostic::do_not_recommend]
impl<T: InternalFormat> PublicFormat for T {}

struct Packet;
impl PublicFormat for Packet {}

fn require_public<T: PublicFormat>(_: T) {}

fn main() {
    require_public(Packet);
}
```

Do not copy examples that implement a foreign trait such as `From` for a foreign target such as `Box<dyn Error>` or `Infallible`; those impls are illegal regardless of the diagnostic attribute.

See [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) for the dedicated rule.

## Design Error Types for the Boundary

A small domain error often needs no dependency:

```rust
use std::fmt;

#[derive(Debug, PartialEq, Eq)]
enum ParsePortError {
    InvalidNumber,
    Reserved,
}

impl fmt::Display for ParsePortError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidNumber => f.write_str("invalid port number"),
            Self::Reserved => f.write_str("port is reserved"),
        }
    }
}

impl std::error::Error for ParsePortError {}
```

Libraries usually benefit from typed public errors callers can match. Applications may prefer a context-oriented dynamic error internally. Choose from the needs of the API boundary rather than applying one error crate everywhere.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — deriving typed library errors
- [err-question-mark](./err-question-mark.md) — `?` propagation
- [type-option-nullable](./type-option-nullable.md) — absence versus failure
- [type-never-diverge](./type-never-diverge.md) — never type and `Infallible`
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) — diagnostic hints
