# err-custom-type

> Define custom error types for domain-specific failures

## Why It Matters

Generic errors like `String`, `Box<dyn Error>`, or catch-all enums obscure what can actually go wrong. Custom error types document failure modes in the type system, enable pattern matching for specific handling, and provide clear API contracts. They make your code self-documenting and help callers handle errors appropriately.

## Bad

```rust
// Generic string errors - no structure
fn validate_user(user: &User) -> Result<(), String> {
    if user.name.is_empty() {
        return Err("Name is empty".to_string());
    }
    if user.age > 150 {
        return Err("Age is invalid".to_string());
    }
    Ok(())
}

// Caller can't match on specific errors
match validate_user(&user) {
    Ok(()) => save(user),
    Err(msg) => {
        // Can only do string comparison - fragile!
        if msg.contains("Name") {
            prompt_for_name()
        }
    }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ValidationError {
    #[error("name cannot be empty")]
    EmptyName,
    
    #[error("name exceeds maximum length of {max} characters")]
    NameTooLong { max: usize, actual: usize },
    
    #[error("invalid age {0}: must be between 0 and 150")]
    InvalidAge(u8),
    
    #[error("email format is invalid: {0}")]
    InvalidEmail(String),
}

fn validate_user(user: &User) -> Result<(), ValidationError> {
    if user.name.is_empty() {
        return Err(ValidationError::EmptyName);
    }
    if user.name.len() > 100 {
        return Err(ValidationError::NameTooLong { 
            max: 100, 
            actual: user.name.len() 
        });
    }
    if user.age > 150 {
        return Err(ValidationError::InvalidAge(user.age));
    }
    Ok(())
}

// Caller can match specifically
match validate_user(&user) {
    Ok(()) => save(user),
    Err(ValidationError::EmptyName) => prompt_for_name(),
    Err(ValidationError::InvalidAge(age)) => {
        show_error(&format!("Please enter a valid age (you entered {})", age))
    }
    Err(e) => show_error(&e.to_string()),
}
```

## Error Type Design Guidelines

```rust
// 1. Group related errors in domain-specific enums
#[derive(Error, Debug)]
pub enum AuthError {
    #[error("invalid credentials")]
    InvalidCredentials,
    #[error("account locked after {attempts} failed attempts")]
    AccountLocked { attempts: u32 },
    #[error("token expired")]
    TokenExpired,
}

#[derive(Error, Debug)]
pub enum PaymentError {
    #[error("insufficient funds: need {required}, have {available}")]
    InsufficientFunds { required: Decimal, available: Decimal },
    #[error("card declined: {reason}")]
    CardDeclined { reason: String },
}

// 2. Include relevant data for error handling/display
#[derive(Error, Debug)]
pub enum FileError {
    #[error("file not found: {path}")]
    NotFound { path: PathBuf },
    #[error("permission denied for {path}")]
    PermissionDenied { path: PathBuf },
}

// 3. Consider #[non_exhaustive] for public APIs
#[derive(Error, Debug)]
#[non_exhaustive]  // Allows adding variants without breaking changes
pub enum ApiError {
    #[error("rate limited")]
    RateLimited,
    #[error("not found")]
    NotFound,
}
```

## thiserror 2.0: no_std Support

thiserror 2.0+ supports `no_std` environments (Rust 1.81+):

```toml
# Cargo.toml
[dependencies]
thiserror = { version = "2", default-features = false }
```

```rust
#![no_std]

use thiserror::Error;

#[derive(Error, Debug)]
pub enum SpiError {
    #[error("DMA transfer failed on channel {channel}")]
    DmaFailed {
        channel: u8,
        #[source]
        source: DmaError,
    },

    #[error("CS assertion failed")]
    CsAssert(#[from] GpioError),
}
```

## #[error(transparent)]

Delegates both Display and source to the inner error, useful for wrapping other error types:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error(transparent)]
    Internal(#[from] InternalError),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    // Without transparent, wrapping is more verbose
    #[error("parse error: {0}")]
    Parse(String),
}
```

## Alternative: snafu 0.9

`snafu` 0.9 (March 2026) provides context selectors and a `Report` macro:

```rust
use snafu::prelude::*;

#[derive(Debug, Snafu)]
pub enum ConfigError {
    #[snafu(display("failed to read config at {path}"))]
    ReadFailed {
        path: String,
        source: std::io::Error,
    },
}

// snafu's Report macro for unified output
fn main() {
    if let Err(e) = run() {
        eprintln!("{}", Report::from_error(e));
        std::process::exit(1);
    }
}
```

## #[diagnostic::do_not_recommend] (Rust 1.85+)

Hide blanket error conversion impls from compiler suggestions:

```rust
#[diagnostic::do_not_recommend]
impl<T: std::error::Error + 'static> From<T> for Box<dyn std::error::Error> {
    fn from(err: T) -> Self {
        Box::new(err)
    }
}
```

## When to Use What

| Error Pattern | Use Case |
|---------------|----------|
| Custom enum | Library with specific failure modes |
| `thiserror` | Libraries needing `std::error::Error` or `core::error::Error` |
| `anyhow::Error` | Applications, prototypes |
| Struct with source | Single error type with wrapped cause |

## Struct-Based Errors

For single error types with rich context:

```rust
#[derive(Error, Debug)]
#[error("query failed for table '{table}' with filter '{filter}'")]
pub struct QueryError {
    pub table: String,
    pub filter: String,
    #[source]
    pub source: DatabaseError,
}
```

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - thiserror for error definitions
- [err-no-std-error](./err-no-std-error.md) - no_std error patterns
- [err-anyhow-app](./err-anyhow-app.md) - When to use anyhow instead
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) - Cleaner compiler diagnostics
- [api-non-exhaustive](./api-non-exhaustive.md) - Forward-compatible enums
