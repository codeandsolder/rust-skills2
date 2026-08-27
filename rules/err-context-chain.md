# err-context-chain

> Add context at abstraction boundaries so an error says what operation failed as well as why

## Why It Matters

Low-level errors usually describe the immediate failure, not the application operation that led to it. `No such file or directory` is useful, but `failed to read user record /srv/users/42.json: No such file or directory` is much better.

Context should add **new** information as an error crosses an abstraction boundary. Repeating the same message at every layer only makes reports longer.

## Bad: Propagate an Opaque Low-Level Error

```rust
use anyhow::Result;
use serde_json::Value;
use std::fs;

fn load_user(path: &str) -> Result<Value> {
    let text = fs::read_to_string(path)?;
    Ok(serde_json::from_str(&text)?)
}

fn main() {}
```

If reading fails, the source error may not say which application resource was being loaded. If parsing fails, it may not say that the JSON was supposed to be a user record.

## Good: Describe the Failed Operation

```rust
use anyhow::{Context, Result};
use serde_json::Value;
use std::fs;

fn load_user(id: u64) -> Result<Value> {
    let path = format!("users/{id}.json");

    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read user file {path}"))?;

    serde_json::from_str(&text)
        .with_context(|| format!("failed to parse JSON for user {id}"))
}

fn main() {}
```

A report can now preserve both layers: the application operation and the underlying I/O or parse error.

## `context` Versus `with_context`

`Context` offers two common forms:

```rust
use anyhow::{Context, Result};
use std::fs;

fn static_context() -> Result<String> {
    fs::read_to_string("config.json")
        .context("failed to read application config")
}

fn dynamic_context(path: &str) -> Result<String> {
    fs::read_to_string(path)
        .with_context(|| format!("failed to read {path}"))
}

fn main() {}
```

- `.context(value)` receives its context value eagerly. Static strings are simple and cheap.
- `.with_context(|| value)` invokes the closure only when the result is an error. Prefer it when the message needs formatting, cloning, or other work.

Do not describe `.context()` as inherently allocating: whether constructing the supplied context allocates depends on the context value you pass.

## Build a Chain by Crossing Real Boundaries

```rust
use anyhow::{Context, Result};

fn read_order(id: u64) -> Result<String> {
    std::fs::read_to_string(format!("orders/{id}.txt"))
        .with_context(|| format!("failed to read order {id}"))
}

fn prepare_order(id: u64) -> Result<String> {
    let order = read_order(id)
        .with_context(|| format!("failed to prepare order {id}"))?;
    Ok(order)
}

fn run() -> Result<()> {
    prepare_order(42).context("startup order preparation failed")?;
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
    }
}
```

Useful context often answers one of these questions:

- Which file, URL, record, user, request, or configuration key was involved?
- Which higher-level operation was attempted?
- Which input identifier matters for reproducing the failure?

## Avoid Redundant Context

This is technically valid but poor reporting:

```rust
use anyhow::{Context, Result};

fn read_config() -> Result<String> {
    std::fs::read_to_string("config.json")
        .context("failed")
        .context("operation failed")
        .context("application operation failed")
}

fn main() {}
```

Every layer should add information, not just another synonym for failure.

## Typed Errors Can Carry Context Structurally

Context does not require `anyhow`. A typed error can store the same information in fields while preserving a source error:

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

fn read_config(path: &str) -> Result<String, ConfigError> {
    std::fs::read_to_string(path).map_err(|source| ConfigError::Read {
        path: path.to_owned(),
        source,
    })
}

fn main() {}
```

Choose structured fields when callers need to inspect them. Choose `anyhow::Context` when the application mainly needs a diagnostic chain.

## Displaying a Chain

```rust
use anyhow::{Context, Result};

fn run() -> Result<()> {
    std::fs::read_to_string("missing.txt")
        .context("failed to load startup data")?;
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        // Compact chain.
        eprintln!("{error:#}");

        // Individual causes.
        for (index, cause) in error.chain().enumerate() {
            eprintln!("{index}: {cause}");
        }
    }
}
```

The outer context should normally describe the higher-level operation; the source error should retain the lower-level cause.

## Async Code Does Not Need a Special `move` Rule

Edition 2024's return-position `impl Trait` capture changes do not imply that every `.with_context(...)` closure in async code must be `move`. Use `move` when ownership/lifetime requirements of the particular closure require it, exactly as with other closures. Do not add it mechanically as an Edition 2024 error-handling rule.

## Practical Guidance

- Add context where an error crosses an abstraction boundary.
- Include identifiers and resource names that help diagnose the failure.
- Prefer `with_context` for dynamically constructed messages.
- Preserve the source error instead of flattening it into a string.
- Avoid context layers that merely restate `failed` or duplicate the source message.
- Use typed fields instead of free-form context when callers need programmatic recovery information.

## See Also

- [err-anyhow-app](./err-anyhow-app.md) - `anyhow` at application boundaries
- [err-source-chain](./err-source-chain.md) - Preserving `Error::source`
- [err-from-impl](./err-from-impl.md) - Error conversions
- [err-question-mark](./err-question-mark.md) - Propagation with `?`
