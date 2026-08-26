# err-thiserror-lib

> Use `thiserror` for library error types

## Why It Matters

Libraries should expose typed, matchable errors so users can handle specific error conditions. `thiserror` generates `Error` trait implementations with minimal boilerplate, creating ergonomic error types that are easy to match against.

## Bad

```rust
// String errors - not matchable
fn parse(input: &str) -> Result<Data, String> {
    Err("parse error".to_string())
}

// Box<dyn Error> - not matchable
fn load(path: &Path) -> Result<Data, Box<dyn std::error::Error>> {
    Err(Box::new(std::io::Error::new(std::io::ErrorKind::NotFound, "file not found")))
}

// Manual implementation - verbose
#[derive(Debug)]
enum MyError {
    Io(std::io::Error),
    Parse(String),
}

impl std::fmt::Display for MyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MyError::Io(e) => write!(f, "io error: {}", e),
            MyError::Parse(s) => write!(f, "parse error: {}", s),
        }
    }
}

impl std::error::Error for MyError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            MyError::Io(e) => Some(e),
            MyError::Parse(_) => None,
        }
    }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ParseError {
    #[error("invalid syntax at line {line}: {message}")]
    Syntax { line: usize, message: String },
    
    #[error("unexpected end of file")]
    UnexpectedEof,
    
    #[error("invalid utf-8 encoding")]
    Utf8(#[from] std::str::Utf8Error),
    
    #[error("io error reading input")]
    Io(#[from] std::io::Error),
}

// Usage
fn parse(input: &str) -> Result<Ast, ParseError> {
    if input.is_empty() {
        return Err(ParseError::UnexpectedEof);
    }
    // ...
}

// Users can match specific errors
match parse(input) {
    Ok(ast) => process(ast),
    Err(ParseError::Syntax { line, message }) => {
        eprintln!("Syntax error on line {}: {}", line, message);
    }
    Err(ParseError::UnexpectedEof) => {
        eprintln!("File ended unexpectedly");
    }
    Err(e) => eprintln!("Error: {}", e),
}
```

## Key Attributes

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MyError {
    // Simple message
    #[error("operation failed")]
    Failed,
    
    // Interpolated fields
    #[error("invalid value: {0}")]
    InvalidValue(String),
    
    // Named fields
    #[error("connection to {host}:{port} failed")]
    Connection { host: String, port: u16 },
    
    // Automatic From impl with #[from]
    #[error("database error")]
    Database(#[from] sqlx::Error),
    
    // Source without From (manual conversion needed)
    #[error("validation failed")]
    Validation {
        #[source]
        cause: ValidationError,
        field: String,
    },
    
    // Transparent - delegates Display and source to inner
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}
```

## Error Chaining

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("failed to read config file")]
    Read(#[source] std::io::Error),
    
    #[error("failed to parse config")]
    Parse(#[source] toml::de::Error),
    
    #[error("invalid config value for '{key}'")]
    InvalidValue {
        key: String,
        #[source]
        cause: ValueError,
    },
}

// Error chain is preserved
fn load_config(path: &Path) -> Result<Config, ConfigError> {
    let content = std::fs::read_to_string(path)
        .map_err(ConfigError::Read)?;
    
    let config: Config = toml::from_str(&content)
        .map_err(ConfigError::Parse)?;
    
    Ok(config)
}
```

## no_std Support (thiserror 2.0+)

thiserror 2.0+ supports `no_std` with `core::error::Error` (Rust 1.81+):

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

// core::error::Error is automatically derived
```

## #[error(transparent)]

Delegates both Display and source to the inner error:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    // Transparent — passes through Display and source
    #[error(transparent)]
    Other(#[from] anyhow::Error),

    // Without transparent, you'd need to specify both
    #[error("io failure")]
    Io(#[from] std::io::Error),
}
```

This is especially useful for wrapping `anyhow::Error` or other dynamic error types in your thiserror enum.

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

This prevents the compiler from suggesting `Box<dyn Error>` conversions when users don't want them.

## Alternative: snafu 0.9

`snafu` 0.9 (March 2026) is an alternative to thiserror with context selectors and a `Report` macro:

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

// snafu's Report macro for unified error reporting
fn main() {
    if let Err(e) = run() {
        eprintln!("{}", Report::from_error(e));
        std::process::exit(1);
    }
}
```

Choose thiserror for simplicity and ecosystem maturity; choose snafu when you need context selectors or prefer its API.

## Library vs Application

| Context | Crate | Why |
|---------|-------|-----|
| Library | `thiserror` | Typed errors users can match |
| Application | `anyhow` | Easy error handling with context |
| Both | `thiserror` for public API, `anyhow` internally | Best of both |

## See Also

- [err-anyhow-app](err-anyhow-app.md) - Use anyhow for applications
- [err-from-impl](err-from-impl.md) - Use #[from] for automatic conversion
- [err-source-chain](err-source-chain.md) - Use #[source] to chain errors
