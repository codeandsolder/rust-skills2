# err-anyhow-app

> Use `anyhow` for application error handling

## Why It Matters

Applications often don't need typed errors - they just need to report what went wrong with good context. `anyhow` provides easy error handling with context chaining, backtraces, and conversion from any error type.

## Bad

```rust
// Tedious type management
fn load_config() -> Result<Config, Box<dyn std::error::Error>> {
    let path = find_config()?;  // Returns FindError
    let content = std::fs::read_to_string(&path)?;  // Returns io::Error
    let config: Config = toml::from_str(&content)?;  // Returns toml::Error
    validate(&config)?;  // Returns ValidationError
    Ok(config)
}

// No context - hard to debug
fn process() -> Result<(), Box<dyn std::error::Error>> {
    let data = fetch()?;  // Which fetch failed?
    transform(data)?;     // What was being transformed?
    save()?;              // Where was it saving to?
    Ok(())
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use anyhow::{Context, Result};

fn load_config() -> Result<Config> {
    let path = find_config()
        .context("failed to locate config file")?;
    
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;
    
    let config: Config = toml::from_str(&content)
        .context("failed to parse config as TOML")?;
    
    validate(&config)
        .context("config validation failed")?;
    
    Ok(config)
}

// Error message: "config validation failed: field 'port' must be > 0"
// Full chain preserved for debugging
```

## Key Features

```rust
use anyhow::{anyhow, bail, ensure, Context, Result};

fn example() -> Result<()> {
    // Create ad-hoc errors
    let err = anyhow!("something went wrong");
    
    // Early return with error
    bail!("aborting due to {}", reason);
    
    // Assert with error
    ensure!(condition, "condition was false");
    
    // Add context to any error
    risky_operation()
        .context("risky operation failed")?;
    
    // Dynamic context
    fetch(url)
        .with_context(|| format!("failed to fetch {}", url))?;
    
    Ok(())
}
```

## Main Function Pattern

```rust
use anyhow::Result;

fn main() -> Result<()> {
    let config = load_config()?;
    run_app(config)?;
    Ok(())
}

// Or with custom exit handling
fn main() {
    if let Err(e) = run() {
        eprintln!("Error: {:#}", e);  // Pretty-print with causes
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    // Application logic
    Ok(())
}
```

## Error Display Formats

```rust
use anyhow::Result;

fn show_error(err: anyhow::Error) {
    // Just the top-level message
    println!("{}", err);
    // "config validation failed"
    
    // With cause chain (# alternate format)
    println!("{:#}", err);
    // "config validation failed: field 'port' must be > 0"
    
    // Debug format with backtrace
    println!("{:?}", err);
    // Full backtrace if RUST_BACKTRACE=1
    
    // Iterate through cause chain
    for cause in err.chain() {
        println!("Caused by: {}", cause);
    }
}
```

## Combining with thiserror

```rust
// In your library crate - typed errors
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ApiError {
    #[error("rate limited")]
    RateLimited,
    #[error("not found: {0}")]
    NotFound(String),
}

// In your application - anyhow for handling
use anyhow::{Context, Result};

fn fetch_user(id: u64) -> Result<User> {
    api::get_user(id)
        .with_context(|| format!("failed to fetch user {}", id))
}

// Can still downcast if needed
fn handle_error(err: anyhow::Error) {
    if let Some(api_err) = err.downcast_ref::<ApiError>() {
        match api_err {
            ApiError::RateLimited => wait_and_retry(),
            ApiError::NotFound(id) => log_missing(id),
        }
    }
}
```

## When to Use Which

| Situation | Use |
|-----------|-----|
| Library public API | `thiserror` |
| Application code | `anyhow` |
| CLI tools | `anyhow` |
| Internal library code | Either |
| Need to match error variants | `thiserror` |
| Just need to report errors | `anyhow` |

## Display Layers: color-eyre and miette

`anyhow` can be combined with display/reporting crates for richer output:

```rust
// color-eyre — colorful, structured error reports
use color_eyre::eyre::Result;

fn main() -> Result<()> {
    color_eyre::install()?; // Backtrace capture + colored output
    run_app()?;
    Ok(())
}

// miette — diagnostic-rich error reports with source snippets
use miette::{Diagnostic, Report, SourceSpan};

#[derive(Debug, Diagnostic, thiserror::Error)]
#[error("parse failed")]
#[diagnostic(help("check the syntax at offset {offset}"))]
struct ParseError {
    offset: usize,
    #[source_code]
    src: String,
    #[label("here")]
    highlight: SourceSpan,
}
```

## #[error(transparent)] with anyhow::Error

`anyhow::Error` can be wrapped in thiserror enums using `#[error(transparent)]`:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error(transparent)]  // Delegates Display and source to inner
    Other(#[from] anyhow::Error),

    #[error("config error: {0}")]
    Config(String),
}

// Now any anyhow-contextualized error can flow into your typed error enum
```

## Rust 1.92+ Improvements

- `unused_must_use` no longer warns on `Result<(), Infallible>` — eliminating a common annoyance with infallible trait impls.
- `assert_matches!` (Rust 1.96) provides better test diagnostics than `assert!(matches!(...))`.
- `From<T> for AssertUnwindSafe<T>` (Rust 1.96) makes `catch_unwind` more ergonomic.

```rust
// Rust 1.96 — assert_matches! in tests
#[test]
fn test_error_kind() {
    assert_matches!(result, Err(Error::NotFound));
}

// Rust 1.96 — ergonomic catch_unwind
use std::panic::{catch_unwind, AssertUnwindSafe};

let result = catch_unwind(AssertUnwindSafe(|| {
    fallible_operation()?;
    Ok(())
}));
```

## See Also

- [err-thiserror-lib](err-thiserror-lib.md) - Use thiserror for libraries
- [err-context-chain](err-context-chain.md) - Add context to errors
- [err-diagnostic-do-not-recommend](err-diagnostic-do-not-recommend.md) - Cleaner compiler diagnostics
