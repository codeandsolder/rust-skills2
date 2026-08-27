# err-source-chain

> Preserve underlying causes in the error source chain

## Why It Matters

Errors often add higher-level context to a lower-level failure. Keeping the original error as a `source()` lets reporters, logs, and callers inspect the chain instead of receiving only a formatted copy of the innermost message.

Converting an error to `String` too early destroys its type, structured fields, and source chain. Keep the error object whenever the underlying cause matters.

## Bad

<!-- rust-check: compile -->
```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum ConfigError {
    #[error("configuration failed: {0}")]
    Failed(String),
}

fn load_config(path: &str) -> Result<u64, ConfigError> {
    let content = std::fs::read_to_string(path)
        .map_err(|error| ConfigError::Failed(error.to_string()))?;

    content
        .trim()
        .parse::<u64>()
        .map_err(|error| ConfigError::Failed(error.to_string()))
}
```

Both lower-level errors are flattened into text. A caller can display the message but cannot recover an `io::Error`, a `ParseIntError`, or a source chain.

## Good

<!-- rust-check: compile -->
```rust
use std::num::ParseIntError;
use thiserror::Error;

#[derive(Error, Debug)]
enum ConfigError {
    #[error("failed to read config file '{path}'")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to parse config file '{path}'")]
    Parse {
        path: String,
        #[source]
        source: ParseIntError,
    },
}

fn load_config(path: &str) -> Result<u64, ConfigError> {
    let content = std::fs::read_to_string(path).map_err(|source| ConfigError::Read {
        path: path.to_owned(),
        source,
    })?;

    content.trim().parse::<u64>().map_err(|source| ConfigError::Parse {
        path: path.to_owned(),
        source,
    })
}
```

The outer error adds which operation/file failed while the original error remains available through `Error::source()`.

## `#[source]` and Field Names

With `thiserror`, a field marked `#[source]` is returned from the generated `Error::source()` implementation. A field literally named `source` is also recognized automatically, so the attribute is optional in that case; keeping it explicit can make the intent clearer in examples.

The source type must itself implement the error trait expected by the generated implementation.

## `#[from]` Implies `#[source]`

A `#[from]` field gets both a `From` conversion and source chaining. Do not add both attributes to the same field.

```rust
use std::num::ParseIntError;
use thiserror::Error;

#[derive(Error, Debug)]
enum NumberError {
    #[error("failed to parse integer")]
    Parse(#[from] ParseIntError),
}

fn parse_number(text: &str) -> Result<u64, NumberError> {
    Ok(text.parse()?)
}
```

Use `#[source]` without `#[from]` when the outer variant also needs context that prevents a one-field automatic conversion:

```rust
use std::num::ParseIntError;
use thiserror::Error;

#[derive(Error, Debug)]
enum FieldError {
    #[error("invalid integer in field '{field}'")]
    Parse {
        field: &'static str,
        #[source]
        source: ParseIntError,
    },
}
```

## Manual `source()` Implementation

You do not need a derive macro to preserve a chain:

```rust
use std::error::Error;
use std::fmt;

#[derive(Debug)]
struct MyError {
    message: String,
    source: Option<Box<dyn Error + Send + Sync>>,
}

impl fmt::Display for MyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for MyError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        self.source
            .as_deref()
            .map(|error| error as &(dyn Error + 'static))
    }
}
```

## Walking the Chain

```rust
fn print_error_chain(error: &dyn std::error::Error) {
    eprintln!("{error}");

    let mut source = error.source();
    while let Some(error) = source {
        eprintln!("caused by: {error}");
        source = error.source();
    }
}
```

Error reporters often do this for you; the important part is preserving the structured sources so they have something to traverse.

## Adding Context with `anyhow`

Application code can attach context without discarding the underlying source:

```rust
use anyhow::{Context, Result};

fn load_number(path: &str) -> Result<u64> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read '{path}'"))?;

    content
        .trim()
        .parse::<u64>()
        .with_context(|| format!("failed to parse '{path}'"))
}
```

The context layer and the original `io::Error`/`ParseIntError` remain in the report chain.

## Do Not Invent a Chain for Mere Text

Sometimes the underlying value is not an error object or its structure is deliberately not part of your API. In that case, storing a message is fine. Preserve sources when there is a meaningful causal error to retain; do not wrap every string merely to manufacture depth.

For `no_std` use of `thiserror`, see [err-no-std-error](./err-no-std-error.md) rather than duplicating feature-sensitive setup here.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Typed error definitions
- [err-no-std-error](./err-no-std-error.md) — `no_std` error patterns
- [err-context-chain](./err-context-chain.md) — Adding operation context
- [err-from-impl](./err-from-impl.md) — `From` conversions for `?`
