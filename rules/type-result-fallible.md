# type-result-fallible

> Use `Result<T, E>` for fallible operations

**Rule**: `type-result-fallible`

## Why It Matters

`Result<T, E>` makes failure explicit in the type system. Callers must acknowledge and handle potential errors — they can't accidentally ignore failures. The `?` operator makes error propagation ergonomic while maintaining explicit error handling.

## Bad

```rust
// Returning Option loses error context
fn read_config(path: &str) -> Option<Config> {
    let content = std::fs::read_to_string(path).ok()?;  // Why did it fail?
    toml::from_str(&content).ok()  // Parse error lost
}

// Panicking on errors
fn read_config(path: &str) -> Config {
    let content = std::fs::read_to_string(path).unwrap();  // Crashes
    toml::from_str(&content).unwrap()  // Crashes
}

// Sentinel values
fn divide(a: i32, b: i32) -> i32 {
    if b == 0 { return -1; }  // Magic value, easy to miss
    a / b
}
```

## Good

```rust
// Result with clear error type
fn read_config(path: &str) -> Result<Config, ConfigError> {
    let content = std::fs::read_to_string(path)
        .map_err(ConfigError::IoError)?;
    toml::from_str(&content)
        .map_err(ConfigError::ParseError)
}

// Explicit error type
fn divide(a: i32, b: i32) -> Result<i32, DivisionError> {
    if b == 0 {
        return Err(DivisionError::DivideByZero);
    }
    Ok(a / b)
}

// Caller must handle
match divide(10, 0) {
    Ok(result) => println!("Result: {}", result),
    Err(e) => println!("Error: {}", e),
}
```

## The `?` Operator

```rust
fn process_file(path: &str) -> Result<ProcessedData, Error> {
    let content = std::fs::read_to_string(path)?;  // Propagates Err
    let parsed: RawData = serde_json::from_str(&content)?;
    let validated = validate(parsed)?;
    Ok(validated)
}
```

## Result Combinators

```rust
let result: Result<i32, Error> = Ok(42);

// map: transform success value
let doubled = result.map(|n| n * 2);  // Ok(84)

// map_err: transform error
let with_context = result.map_err(|e| format!("Failed: {}", e));

// and_then: chain fallible operations
let processed = result.and_then(|n| {
    if n > 0 { Ok(n * 2) } else { Err(Error::Negative) }
});

// unwrap_or: provide default on error
let value = result.unwrap_or(0);

// ok(): convert to Option, discarding error
let maybe_value: Option<i32> = result.ok();
```

## `Result::flatten` (Rust 1.89+)

Eliminate boilerplate when dealing with nested `Result<Result<T, E>, E>`:

```rust
// Before: manual double-unwrap
fn get_first(items: &[Result<i32, Error>]) -> Result<i32, Error> {
    items.first().copied().unwrap_or(Err(Error::Empty))
}

// Nested Result: Result<Result<T, E>, E>
let nested: Result<Result<i32, ()>, ()> = Ok(Ok(42));

// Before flatten: manual match
let value = match nested {
    Ok(Ok(v)) => Ok(v),
    Ok(Err(e)) => Err(e),
    Err(e) => Err(e),
};

// After flatten (Rust 1.89+): single method call
let value: Result<i32, ()> = nested.flatten();  // Ok(42)

// Useful with iterators
fn process_all(items: Vec<Result<i32, Error>>) -> Result<Vec<i32>, Error> {
    items.into_iter().collect::<Result<Vec<_>, _>>()
}
```

## `unused_must_use` + `Uninhabited` (Rust 1.92+)

Since Rust 1.92, the `unused_must_use` lint no longer warns on `Result<(), UninhabitedType>` or `ControlFlow<UninhabitedType, ()>`. The most common case is `Infallible`, but the exemption applies to any uninhabited error type (including user-defined empty enums):

```rust
use std::convert::Infallible;

/// Returns a value that is always Ok — the error case is
/// statically impossible.
fn compute() -> Result<i32, Infallible> {
    Ok(42)
}

// No warning — Err branch is statically unreachable
compute();

// Also exempt: ControlFlow<Infallible, ()>
fn control() -> ControlFlow<Infallible, ()> {
    ControlFlow::Continue(())
}
control();

// With a real error type, the must_use lint applies:
fn fallible() -> Result<i32, Error> {
    Ok(42)
}
// fallible(); // Warning: unused Result that must be used
```

## `#[diagnostic::do_not_recommend]` (Rust 1.85+)

Hide implementation details from compiler error messages. Useful when a blanket `From<T>` implementation would otherwise appear in suggestions:

```rust
use std::convert::Infallible;

#[diagnostic::do_not_recommend]
impl<T> From<T> for Infallible {
    fn from(_: T) -> Self {
        // Since Infallible can never be constructed, this
        // impl only exists for type compatibility. The
        // diagnostic hint prevents the compiler from
        // suggesting it in error messages.
        match Some(()) { None => unreachable!(), _ => todo!() }
    }
}

// Without #[diagnostic::do_not_recommend], when the compiler
// can't find a matching From impl, it might suggest using
// this one — which would be incorrect. The attribute hides it
// from suggestions.
```

## Defining Error Types

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("failed to read file: {0}")]
    Io(#[from] std::io::Error),

    #[error("failed to parse config: {0}")]
    Parse(#[from] toml::de::Error),

    #[error("missing required field: {0}")]
    MissingField(String),
}

fn load_config(path: &str) -> Result<Config, ConfigError> {
    let content = std::fs::read_to_string(path)?;  // Io error
    let config: Config = toml::from_str(&content)?;  // Parse error
    if config.name.is_empty() {
        return Err(ConfigError::MissingField("name".into()));
    }
    Ok(config)
}
```

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Defining error types
- [err-question-mark](./err-question-mark.md) — Using `?` operator
- [type-option-nullable](./type-option-nullable.md) — `Option` vs `Result`
- [type-never-diverge](./type-never-diverge.md) — `!` type and `Infallible`
- [Rust 1.89: Result::flatten](https://blog.rust-lang.org/2025/08/07/Rust-1.89.0/)
- [Rust 1.92: Never type lints deny-by-default](https://blog.rust-lang.org/2025/12/11/Rust-1.92.0)
