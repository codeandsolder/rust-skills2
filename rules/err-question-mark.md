# err-question-mark

> Use `?` operator for clean propagation

## Why It Matters

The `?` operator is Rust's idiomatic way to propagate errors. It's concise, readable, and automatically converts between compatible error types using `From`. It replaces verbose `match` or `unwrap()` calls.

## Bad

```rust
// Verbose match-based error handling
fn load_config() -> Result<Config, Error> {
    let content = match std::fs::read_to_string("config.toml") {
        Ok(c) => c,
        Err(e) => return Err(Error::Io(e)),
    };
    
    let config = match toml::from_str(&content) {
        Ok(c) => c,
        Err(e) => return Err(Error::Parse(e)),
    };
    
    Ok(config)
}

// Or worse - using unwrap
fn load_config_bad() -> Config {
    let content = std::fs::read_to_string("config.toml").unwrap();
    toml::from_str(&content).unwrap()
}
```

## Good

```rust
fn load_config() -> Result<Config, Error> {
    let content = std::fs::read_to_string("config.toml")?;
    let config = toml::from_str(&content)?;
    Ok(config)
}

// Even more concise
fn load_config() -> Result<Config, Error> {
    Ok(toml::from_str(&std::fs::read_to_string("config.toml")?)?)
}
```

## How ? Works

```rust
// This:
let x = expr?;

// Expands roughly to:
let x = match expr {
    Ok(val) => val,
    Err(err) => return Err(From::from(err)),
};
```

## Combining with Context

```rust
use anyhow::{Context, Result};

fn load_user(id: u64) -> Result<User> {
    let path = format!("users/{}.json", id);
    
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read user file: {}", path))?;
    
    let user: User = serde_json::from_str(&content)
        .context("failed to parse user JSON")?;
    
    Ok(user)
}
```

## ? with Option

```rust
fn get_first_word(text: &str) -> Option<&str> {
    let first_line = text.lines().next()?;
    let first_word = first_line.split_whitespace().next()?;
    Some(first_word)
}

// Convert Option to Result
fn get_required_config(key: &str) -> Result<String, Error> {
    config.get(key)
        .cloned()
        .ok_or_else(|| Error::MissingConfig(key.to_string()))
}
```

## Error Type Conversion

```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum MyError {
    #[error("io error")]
    Io(#[from] std::io::Error),  // Auto From impl
    
    #[error("parse error")]
    Parse(#[from] serde_json::Error),  // Auto From impl
}

fn process() -> Result<(), MyError> {
    // ? automatically converts io::Error to MyError via From
    let content = std::fs::read_to_string("file.txt")?;
    
    // ? automatically converts serde_json::Error to MyError
    let data: Data = serde_json::from_str(&content)?;
    
    Ok(())
}
```

## In main()

```rust
// Option 1: Return Result from main
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = load_config()?;
    run_app(config)?;
    Ok(())
}

// Option 2: Handle in main, exit on error
fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {:#}", e);
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let config = load_config()?;
    run_app(config)?;
    Ok(())
}
```

## try Blocks (Experimental)

`try {}` blocks (tracking issue #154391) provide scoped `?` propagation but remain experimental as of Rust 1.96:

```rust
#![feature(try_blocks)]

fn process_items(items: &[Item]) -> Result<Vec<Output>, Error> {
    let results: Vec<Output> = items
        .iter()
        .filter_map(|item| {
            // try block allows ? inside a closure
            try { process(item)? }
        })
        .collect();
    Ok(results)
}
```

For stable Rust, use `Iterator::collect` with `Result` or nested functions instead. See [err-try-block-experimental](./err-try-block-experimental.md) for details.

## #[diagnostic::do_not_recommend] (Rust 1.85+)

On blanket `From` impls, this attribute prevents the compiler from suggesting unwanted conversions:

```rust
#[diagnostic::do_not_recommend]
impl<T: std::error::Error + 'static> From<T> for Box<dyn std::error::Error> {
    fn from(err: T) -> Self {
        Box::new(err)
    }
}
```

This keeps compiler diagnostics focused on the actual problem rather than suggesting `Box<dyn Error>` conversions.

## See Also

- [err-context-chain](err-context-chain.md) - Add context with .context()
- [err-from-impl](err-from-impl.md) - Use #[from] for automatic conversion
- [err-try-block-experimental](err-try-block-experimental.md) - Experimental try blocks
- [err-diagnostic-do-not-recommend](err-diagnostic-do-not-recommend.md) - Cleaner compiler diagnostics
- [err-anyhow-app](err-anyhow-app.md) - Use anyhow for applications
