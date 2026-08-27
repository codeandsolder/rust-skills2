# err-from-impl

> Implement specific `From<SourceError>` conversions when the conversion is unconditional, unambiguous, and preserves the information callers need

## Why It Matters

For `Result`, the `?` operator can convert the residual error into the function's return error type. The standard `Result` residual conversion uses `From`, so a suitable `From<SourceError> for AppError` lets `?` propagate the source error without a manual `.map_err(...)` at every call site.

That convenience is valuable only when the conversion has one sensible meaning. Do not add broad `From` implementations merely to make `?` compile: conversions become part of the API and can erase context or make future variants difficult to distinguish.

## Good: Specific, Lossless Wrapping

```rust
use std::io;
use std::num::ParseIntError;
use thiserror::Error;

#[derive(Debug, Error)]
enum AppError {
    #[error("failed to read input")]
    Io(#[from] io::Error),

    #[error("input was not an integer")]
    ParseInt(#[from] ParseIntError),
}

fn read_number(path: &str) -> Result<u64, AppError> {
    let text = std::fs::read_to_string(path)?;
    Ok(text.trim().parse()?)
}

fn main() {}
```

`thiserror`'s `#[from]` generates the corresponding `From` implementation and also treats the wrapped field as the error source.

## Manual `From` Is the Same Contract

You do not need a derive macro:

```rust
use std::fmt;
use std::io;

#[derive(Debug)]
enum AppError {
    Io(io::Error),
}

impl From<io::Error> for AppError {
    fn from(source: io::Error) -> Self {
        Self::Io(source)
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(_) => f.write_str("I/O operation failed"),
        }
    }
}

impl std::error::Error for AppError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(source) => Some(source),
        }
    }
}

fn read(path: &str) -> Result<String, AppError> {
    Ok(std::fs::read_to_string(path)?)
}

fn main() {}
```

Use manual implementations when conversion needs custom logic that still represents a true unconditional conversion.

## Add Call-Site Context with `map_err`

A `From<io::Error>` cannot know which path or operation produced the error. If that information belongs in the typed error, construct the variant at the call site instead:

```rust
use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("failed to read config from {path}")]
    Read {
        path: String,
        #[source]
        source: io::Error,
    },
}

fn load_config(path: &str) -> Result<String, ConfigError> {
    std::fs::read_to_string(path).map_err(|source| ConfigError::Read {
        path: path.to_owned(),
        source,
    })
}

fn main() {}
```

Do not force this into `From<io::Error>`: the conversion lacks the `path` needed to construct the useful error.

## `#[from]` Cannot Invent Extra Context

A `thiserror` variant using `#[from]` is for direct conversion from the source error. If the variant needs additional application data, construct it explicitly as above.

A simple direct variant is ideal:

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ParseError {
    #[error("integer parse failed")]
    Integer(#[from] std::num::ParseIntError),
}

fn parse(input: &str) -> Result<u32, ParseError> {
    Ok(input.parse()?)
}

fn main() {}
```

## Avoid Blanket Error Conversions

This shape is usually both semantically poor and, for a normal error type, conflicts with Rust's blanket identity conversion:

```text
impl<E: std::error::Error> From<E> for AppError {
    fn from(error: E) -> Self {
        AppError::Other(error.to_string())
    }
}
```

Problems include:

- `From<T> for T` already exists, so a sufficiently broad implementation overlaps when `E = AppError`.
- converting to a string discards the concrete source type and source chain unless you rebuild them separately;
- every new dependency error silently acquires the same conversion, even when callers would benefit from a distinct variant;
- adding another more-specific conversion later can run into coherence constraints.

Prefer explicit source types or an application report type such as `anyhow::Error` when genuinely arbitrary error aggregation is the requirement.

## `From` Should Be Infallible

`From` represents a conversion that cannot fail. If converting one error representation to another can itself fail or depends on validation, use `TryFrom`, a constructor returning `Result`, or explicit mapping instead of hiding failure inside a `From` implementation.

## Preserve Structured Sources

When an outer error is caused by an inner error, preserve the source rather than formatting it into the outer message and throwing the value away:

```rust
use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
#[error("cache initialization failed")]
struct CacheError {
    #[source]
    source: io::Error,
}

fn initialize() -> Result<(), CacheError> {
    std::fs::File::open("cache.db")
        .map(|_| ())
        .map_err(|source| CacheError { source })
}

fn main() {}
```

This lets reporting layers traverse `Error::source()` while the outer `Display` remains concise.

## Decision Guide

| Conversion shape | Usually prefer |
|---|---|
| one source type maps directly to one error variant | `From` / `#[from]` |
| conversion needs path/request/user context | explicit `map_err` / constructor |
| conversion can fail | `TryFrom` or explicit fallible function |
| arbitrary application errors mainly need reporting | `anyhow`-style report type |
| callers need to distinguish source categories | explicit typed variants |

## Practical Guidance

- Add `From` only when the conversion has one unsurprising meaning.
- Preserve the original source error whenever it remains diagnostically useful.
- Use `#[from]` for direct wrappers; use `map_err` when call-site data is required.
- Avoid generic `From<E>` catch-alls for error enums.
- Remember that `?` convenience is a consequence of the error conversion design, not a reason to make the design broader than it should be.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - Defining typed errors
- [err-source-chain](./err-source-chain.md) - Preserving error sources
- [err-context-chain](./err-context-chain.md) - Adding operation context
- [err-question-mark](./err-question-mark.md) - Propagation with `?`
