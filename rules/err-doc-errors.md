# err-doc-errors

> Document meaningful `Err` conditions in a `# Errors` section

## Why It Matters

Callers need to know which failures an API reports and what they mean. For public fallible functions, a `# Errors` section is the conventional place to describe the conditions that produce `Err`, especially when callers may want to distinguish variants or retry classes.

Document the contract rather than merely restating the return type. If an underlying implementation detail is not part of the API contract, avoid promising its exact error variant unnecessarily.

## Bad

```rust
use std::{io, path::Path};

/// Loads a configuration file.
fn load_config(path: &Path) -> io::Result<String> {
    std::fs::read_to_string(path)
}

fn main() {}
```

The type says the operation may fail, but users still have to infer why.

## Good

```rust
use std::{fs, io, path::Path};

/// Loads a UTF-8 configuration file.
///
/// # Errors
///
/// Returns an [`io::Error`] if the file cannot be opened or read, or if its
/// contents are not valid UTF-8.
pub fn load_config(path: &Path) -> io::Result<String> {
    fs::read_to_string(path)
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseError {
    Empty,
    InvalidDigit,
}

/// Parses a non-empty ASCII decimal number.
///
/// # Errors
///
/// Returns [`ParseError::Empty`] when `input` is empty and
/// [`ParseError::InvalidDigit`] when any byte is not an ASCII digit.
pub fn parse_decimal(input: &str) -> Result<u64, ParseError> {
    if input.is_empty() {
        return Err(ParseError::Empty);
    }
    if !input.bytes().all(|b| b.is_ascii_digit()) {
        return Err(ParseError::InvalidDigit);
    }

    Ok(input.bytes().fold(0, |n, b| n * 10 + u64::from(b - b'0')))
}

fn main() {}
```

Link concrete variants when those variants are part of the caller-facing contract. Use broader prose when the implementation may change while the semantic failure condition stays the same.

## Errors vs Panics

`# Errors` describes returned failures. `# Panics` describes conditions that make a function panic. Keep the two contracts separate.

```rust
/// Divides `dividend` by `divisor`.
///
/// # Errors
///
/// Returns `DivideError` when `divisor` is zero.
#[derive(Debug)]
struct DivideError;

fn divide(dividend: i64, divisor: i64) -> Result<i64, DivideError> {
    if divisor == 0 {
        Err(DivideError)
    } else {
        Ok(dividend / divisor)
    }
}

fn main() {}
```

If an API can both return an error and panic for distinct reasons, document both sections. Do not label an ordinary recoverable error as a panic or vice versa.

## Clippy

Clippy's `missing_errors_doc` lint can enforce this convention for public fallible functions:

```toml
[lints.clippy]
missing_errors_doc = "warn"
```

Use lint suppression deliberately. Rust 1.81 stabilized `#[expect]`, which is useful when you want the build to tell you that a suppression has become unnecessary:

```rust
use std::io;

#[expect(
    clippy::missing_errors_doc,
    reason = "internal adapter mirrors the documented public API"
)]
pub fn internal_adapter() -> io::Result<()> {
    Ok(())
}

fn main() {}
```

`#[expect]` is not mechanically superior to `#[allow]`; use it when an unfulfilled expectation is useful maintenance feedback. A long-lived intentional policy exception may still be clearer with an appropriately reasoned lint configuration.

## What to Document

Prefer statements such as:

- what input or external condition causes the error;
- whether a named error variant is guaranteed;
- whether partial side effects may already have occurred;
- retry-relevant distinctions when they are part of the contract.

Avoid duplicating every implementation branch when those details are not stable API behavior.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Examples in documentation
- [err-thiserror-lib](./err-thiserror-lib.md) - Defining error types
- [api-must-use](./api-must-use.md) - Marking results as must-use
