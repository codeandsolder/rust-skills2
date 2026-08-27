# err-thiserror-lib

> Use `thiserror` to derive typed library errors when it removes boilerplate without hiding the API

## Why It Matters

Library callers often need structured errors they can match and inspect. `thiserror` derives `Display` and `Error` implementations while leaving the resulting error type as an ordinary enum or struct in your public API.

The crate is a boilerplate tool, not a substitute for error design. Choose meaningful variants, decide which source errors should be exposed, and avoid conversions that erase context.

## Good: A Matchable Error Enum

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ParseError {
    #[error("invalid syntax at line {line}: {message}")]
    Syntax { line: usize, message: String },

    #[error("unexpected end of input")]
    UnexpectedEof,

    #[error("invalid UTF-8")]
    Utf8(#[from] std::str::Utf8Error),
}

fn parse(input: &[u8]) -> Result<&str, ParseError> {
    if input.is_empty() {
        return Err(ParseError::UnexpectedEof);
    }
    Ok(std::str::from_utf8(input)?)
}

fn main() {
    assert!(matches!(parse(b""), Err(ParseError::UnexpectedEof)));
}
```

Callers can match variants without depending on human-readable `Display` text.

## `#[from]` Generates Conversion and Source Wiring

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum LoadError {
    #[error("I/O failure")]
    Io(#[from] std::io::Error),
}

fn read(path: &std::path::Path) -> Result<String, LoadError> {
    Ok(std::fs::read_to_string(path)?)
}
```

Use `#[from]` when conversion from that source type is unambiguous and no extra context is required. If construction needs fields such as a path, query, or operation name, use `#[source]` and build the variant explicitly.

## `#[source]` Without Automatic Conversion

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("failed to read {path}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
}

fn load(path: &str) -> Result<String, ConfigError> {
    std::fs::read_to_string(path).map_err(|source| ConfigError::Read {
        path: path.to_owned(),
        source,
    })
}
```

This preserves both domain context and the original error chain.

## `#[error(transparent)]`

Transparent wrappers delegate their `Display` and error source behavior to the wrapped error. Use them when the wrapper intentionally adds no user-facing context.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum AppError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
}
```

If the wrapper represents a distinct domain operation, a contextual message is usually more useful than transparency.

## Public Compatibility Still Matters

Changing variants, fields, or source types can affect downstream matching even though `thiserror` generated the trait implementations. For a public enum expected to grow, consider `#[non_exhaustive]`.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
#[non_exhaustive]
pub enum ClientError {
    #[error("request timed out")]
    Timeout,

    #[error("server rejected the request")]
    Rejected,
}
```

## `no_std`

Modern `thiserror` supports `core::error::Error`-based use in `no_std` configurations. Whether a particular error type is actually `no_std`-friendly still depends on its fields and dependencies.

For a crate that does not need `std`, configure dependencies and features deliberately rather than assuming the derive alone makes the whole error graph `no_std`.

## `#[diagnostic::do_not_recommend]` Is Independent of `thiserror`

Rust 1.85's `#[diagnostic::do_not_recommend]` can hide a **legal trait impl** from compiler recommendations when surfacing that impl would mislead users. It is not a `thiserror` feature and does not make illegal conversion impls valid.

```rust
trait InternalConversion {}
trait PublicConversion {}

#[diagnostic::do_not_recommend]
impl<T: InternalConversion> PublicConversion for T {}

struct Direct;
impl PublicConversion for Direct {}

fn main() {}
```

Do not demonstrate the attribute by implementing foreign `From<T>` for foreign `Box<dyn Error>`: that violates Rust's orphan rules before diagnostics are relevant.

See [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) for the dedicated guidance.

## Library vs Application Boundaries

| Situation | Typical approach |
|---|---|
| Public library failures callers should distinguish | typed `thiserror` enum/struct |
| Application top-level plumbing | often a context-oriented dynamic error |
| Library internals with one obvious source | small custom error or transparent wrapper |
| Failure needing operation/path/query context | explicit variant with `#[source]` |

Avoid turning “libraries use thiserror, applications use anyhow” into a hard law. A binary can benefit from typed domain errors, and a library may use dynamic errors internally while keeping its public boundary typed.

## See Also

- [err-custom-type](./err-custom-type.md) — designing domain errors
- [err-anyhow-app](./err-anyhow-app.md) — application error context
- [err-from-impl](./err-from-impl.md) — error conversions
- [err-source-chain](./err-source-chain.md) — preserving causes
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) — diagnostic hints
