# err-source-chain

> Preserve error chains with `#[source]` or `source()` method

## Why It Matters

Errors often have underlying causes. Preserving the error chain (via `source()` method) allows logging frameworks and error reporters to show the full context: "config parse failed → JSON syntax error at line 5 → unexpected token". Without chaining, you lose valuable debugging information.

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding application error context -->
```rust
#[derive(Debug)]
enum ConfigError {
    ParseFailed(String),  // Lost the original serde_json::Error
}

fn load_config(path: &str) -> Result<Config, ConfigError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| ConfigError::ParseFailed(e.to_string()))?;  // Chain lost!
    
    serde_json::from_str(&content)
        .map_err(|e| ConfigError::ParseFailed(e.to_string()))?  // No source
}

// Error output: "Parse failed: invalid type: ..."
// Missing: which file? what line? what was the parent error?
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum ConfigError {
    #[error("Failed to read config file '{path}'")]
    ReadFailed {
        path: String,
        #[source]  // Preserves the error chain
        source: std::io::Error,
    },
    
    #[error("Failed to parse config file '{path}'")]
    ParseFailed {
        path: String,
        #[source]  // Original parse error preserved
        source: serde_json::Error,
    },
}

fn load_config(path: &str) -> Result<Config, ConfigError> {
    let content = std::fs::read_to_string(path)
        .map_err(|source| ConfigError::ReadFailed {
            path: path.to_string(),
            source,  // Chain preserved
        })?;
    
    serde_json::from_str(&content)
        .map_err(|source| ConfigError::ParseFailed {
            path: path.to_string(),
            source,
        })
}
```

## Manual source() Implementation

```rust
use std::error::Error;

#[derive(Debug)]
struct MyError {
    message: String,
    source: Option<Box<dyn Error + Send + Sync>>,
}

impl std::fmt::Display for MyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl Error for MyError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        self.source.as_ref().map(|e| e.as_ref() as &(dyn Error + 'static))
    }
}
```

## Walking the Error Chain

```rust
fn print_error_chain(error: &dyn std::error::Error) {
    eprintln!("Error: {}", error);
    
    let mut source = error.source();
    while let Some(err) = source {
        eprintln!("Caused by: {}", err);
        source = err.source();
    }
}

// With anyhow, use {:?} for full chain
let result: anyhow::Result<()> = do_something();
if let Err(e) = result {
    eprintln!("{:?}", e);  // Prints full chain with backtraces
}
```

## anyhow Context

```rust
use anyhow::{Context, Result};

fn load_config(path: &str) -> Result<Config> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read '{}'", path))?;
    
    let config: Config = serde_json::from_str(&content)
        .with_context(|| format!("Failed to parse '{}'", path))?;
    
    Ok(config)
}

// Output:
// Error: Failed to parse 'config.json'
// Caused by: expected `:` at line 5 column 10
```

## #[from] vs #[source]

```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum MyError {
    // #[from] = implements From + sets source
    #[error("IO error")]
    Io(#[from] std::io::Error),
    
    // #[source] = only sets source (no From impl)
    #[error("Parse error in file '{path}'")]
    Parse {
        path: String,
        #[source]
        source: serde_json::Error,
    },
}
```

## #[source] in no_std

Since thiserror 2.0+ and Rust 1.81+, `#[source]` works in `no_std` environments:

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
}
```

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - thiserror for error definitions
- [err-no-std-error](./err-no-std-error.md) - no_std error patterns
- [err-context-chain](./err-context-chain.md) - Adding context to errors
- [err-from-impl](./err-from-impl.md) - From implementations for ?
