# doc-errors-section

> Document meaningful failure conditions in a `# Errors` section

## Why It Matters

A `Result` type says that an operation can fail; it usually does not tell callers which conditions produce which errors. Public fallible APIs should document the failure modes callers need to reason about, especially when several error variants or propagated failures are possible.

A useful `# Errors` section describes **conditions**, not merely “returns an error on failure.”

## Bad

<!-- rust-check: compile -->
```rust
use std::path::Path;

pub struct Connection;
pub struct DbError;

/// Opens a file and reads its contents.
pub fn read_file(path: &Path) -> Result<String, std::io::Error> {
    std::fs::read_to_string(path)
}

/// Connects to the database.
pub async fn connect(_url: &str) -> Result<Connection, DbError> {
    Ok(Connection)
}
```

Both functions are valid, but their public documentation leaves callers to infer the failure conditions from implementation details or error types.

## Good

<!-- rust-check: compile -->
```rust
use std::path::Path;

/// Opens a file and reads its contents as UTF-8 text.
///
/// # Errors
///
/// Returns an I/O error if the file cannot be opened or read. Invalid UTF-8
/// is reported as [`std::io::ErrorKind::InvalidData`].
pub fn read_file(path: &Path) -> Result<String, std::io::Error> {
    std::fs::read_to_string(path)
}

/// An established database connection.
pub struct Connection;

/// Failures that can occur while establishing a connection.
pub enum DbError {
    /// `url` does not identify a supported database endpoint.
    InvalidUrl,
    /// The endpoint could not be reached.
    ConnectionFailed,
    /// The supplied credentials were rejected.
    AuthenticationFailed,
    /// No connection slot is currently available.
    PoolExhausted,
}

/// Establishes a database connection.
///
/// # Errors
///
/// Returns:
/// - [`DbError::InvalidUrl`] for an empty URL,
/// - [`DbError::ConnectionFailed`] for an unreachable endpoint,
/// - [`DbError::AuthenticationFailed`] when authentication fails, or
/// - [`DbError::PoolExhausted`] when no connection slot is available.
pub async fn connect(url: &str) -> Result<Connection, DbError> {
    match url {
        "" => Err(DbError::InvalidUrl),
        "offline" => Err(DbError::ConnectionFailed),
        "unauthorized" => Err(DbError::AuthenticationFailed),
        "pool-full" => Err(DbError::PoolExhausted),
        _ => Ok(Connection),
    }
}
```

## Simple Single Error

When the error type already carries the details, keep the section concise:

```rust
use std::num::ParseIntError;

/// Parses a decimal integer.
///
/// # Errors
///
/// Returns [`ParseIntError`] if `text` is not a valid `i64`.
pub fn parse_int(text: &str) -> Result<i64, ParseIntError> {
    text.parse()
}
```

## Multiple Variants

Tables or lists work well when callers need to map variants to conditions:

```rust
pub struct Request {
    pub url: String,
}

pub struct Response;

pub enum HttpError {
    Timeout,
    InvalidUrl,
    ConnectionRefused,
    TlsError,
}

/// Sends `request` and returns the response.
///
/// # Errors
///
/// | Error | Condition |
/// |-------|-----------|
/// | [`HttpError::Timeout`] | The request exceeded its deadline |
/// | [`HttpError::InvalidUrl`] | The URL is empty or malformed |
/// | [`HttpError::ConnectionRefused`] | The peer refused the connection |
/// | [`HttpError::TlsError`] | TLS setup failed |
pub fn send(request: Request) -> Result<Response, HttpError> {
    if request.url.is_empty() {
        Err(HttpError::InvalidUrl)
    } else {
        Ok(Response)
    }
}
```

The implementation may delegate these checks to lower layers; the documentation should still describe the caller-visible contract rather than every internal branch.

## Propagated Errors

If a function transparently propagates another API's errors, describe the relevant source and add context when it helps callers understand the operation that failed.

```rust
use std::fs;
use std::io;
use std::path::Path;

/// Loads configuration text from `path`.
///
/// # Errors
///
/// Returns the underlying [`io::Error`] if the configuration file cannot be
/// opened or read.
pub fn load_config(path: &Path) -> Result<String, io::Error> {
    fs::read_to_string(path)
}
```

Do not promise specific variants that the implementation does not actually preserve. If an error is wrapped or erased, document the stable failure semantics callers can rely on.

## Link Error Types and Variants

Intra-doc links make variant-heavy error documentation easier to navigate:

```rust
pub enum ValidationError {
    TooShort,
    InvalidChars,
}

/// Validates `input`.
///
/// # Errors
///
/// Returns [`ValidationError::TooShort`] for fewer than three characters and
/// [`ValidationError::InvalidChars`] when non-ASCII characters are present.
pub fn validate(input: &str) -> Result<(), ValidationError> {
    if input.len() < 3 {
        Err(ValidationError::TooShort)
    } else if !input.is_ascii() {
        Err(ValidationError::InvalidChars)
    } else {
        Ok(())
    }
}
```

## Clippy Enforcement

`clippy::missing_errors_doc` is a pedantic, allow-by-default lint that checks publicly visible functions returning `Result` and warns when their doc comments lack a `# Errors` section:

```rust
#![warn(clippy::missing_errors_doc)]
```

Its `check-private-items` configuration can extend the check to private items when a project deliberately wants that policy.

A lint can detect a missing section; it cannot determine whether the section accurately describes the implementation. Keep error documentation synchronized with behavior and error conversions.

## See Also

- [doc-panics-section](./doc-panics-section.md) - Documenting panics
- [err-doc-errors](./err-doc-errors.md) - Error documentation patterns
- [doc-intra-links](./doc-intra-links.md) - Linking to types and variants
