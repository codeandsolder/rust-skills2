# err-diagnostic-do-not-recommend

> Use `#[diagnostic::do_not_recommend]` to hide blanket error conversion impls from compiler suggestions

## Why It Matters

When you implement blanket `From<...>` for your error type, the compiler may suggest using those conversions in error messages — even when they're not what the user wants. `#[diagnostic::do_not_recommend]` (Rust 1.85+) tells the compiler to suppress its suggestion for that impl, producing cleaner, more actionable diagnostics.

## Bad

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("io error")]
    Io(#[from] std::io::Error),

    #[error("config error: {0}")]
    Config(String),
}

// The user writes this:
fn load_config() -> Result<(), AppError> {
    std::fs::read_to_string("config.toml")?;
    // Compiler suggests: "help: consider using `Box<dyn std::error::Error>`"
    // or suggests importing AppError::Io variant
    // These suggestions are noisy and not helpful
    Ok(())
}

// Blanket impl that causes noisy suggestions:
impl<T: std::error::Error + 'static> From<T> for Box<dyn std::error::Error> {
    fn from(err: T) -> Self {
        Box::new(err)
    }
}
```

## Good

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("io error")]
    Io(#[from] std::io::Error),

    #[error("config error: {0}")]
    Config(String),
}

// Hide blanket impls from compiler suggestions
#[diagnostic::do_not_recommend]
impl<T: std::error::Error + 'static> From<T> for Box<dyn std::error::Error> {
    fn from(err: T) -> Self {
        Box::new(err)
    }
}

// Now the compiler won't suggest this conversion in error messages
```

## With thiserror and Custom From Impls

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ParseError {
    #[error("invalid token at position {pos}")]
    InvalidToken { pos: usize },
}

// A conversion that exists for convenience but should not appear in suggestions
#[diagnostic::do_not_recommend]
impl From<&str> for ParseError {
    fn from(msg: &str) -> Self {
        ParseError::InvalidToken { pos: 0 }
    }
}
```

## Effect on Compiler Diagnostics

Without `#[diagnostic::do_not_recommend]`:

```
error[E0277]: the trait bound `MyType: From<SomeError>` is not satisfied
  --> src/main.rs:42:5
   |
42 |     let x: MyType = some_error.into();
   |                    ^^^^^^^^ the trait `From<SomeError>` is not implemented for `MyType`
   |
   = help: consider using `Box<dyn std::error::Error>` instead
   = help: or consider importing `some_crate::SomeError`
```

With `#[diagnostic::do_not_recommend]`:

```
error[E0277]: the trait bound `MyType: From<SomeError>` is not satisfied
  --> src/main.rs:42:5
   |
42 |     let x: MyType = some_error.into();
   |                    ^^^^^^^^ the trait `From<SomeError>` is not implemented for `MyType`
   |
   = help: note: a conversion from `SomeError` to `MyType` requires implementing `From<SomeError>`
```

The noisy suggestion for `Box<dyn std::error::Error>` is gone.

## When to Apply

| Situation | Apply `#[diagnostic::do_not_recommend]`? |
|-----------|----------------------------------------|
| Blanket `From<E> for Box<dyn Error>` | Yes |
| Convenience `From<&str>` for error types | Yes |
| Core domain `From` impls that users should use | No |
| `#[from]` on thiserror enum variants | No (already concrete) |

## See Also

- [err-from-impl](./err-from-impl.md) — From implementations for ?
- [err-custom-type](./err-custom-type.md) — Custom error types
- [err-question-mark](./err-question-mark.md) — The ? operator
