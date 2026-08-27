# err-lowercase-msg

> Keep `Error` display messages concise, usually lowercase, and usually without trailing punctuation so they compose cleanly

## Why It Matters

Rust's `Error` documentation says error messages are **typically concise lowercase sentences without trailing punctuation**. That convention is useful because error displays are often embedded in larger reports or chained with context.

It is a convention, not a grammar law. Proper nouns, protocol names, acronyms, identifiers, and error codes keep their normal spelling.

## Bad: Sentence-Style Fragments That Compose Poorly

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("Failed to read configuration.")]
    Read,

    #[error("Invalid JSON format!")]
    Parse,
}

fn main() {}
```

An outer report such as `failed to start service: {error}` now gets mid-chain capitalization and punctuation that reads awkwardly.

## Good: Concise Error Displays

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("failed to read configuration")]
    Read,

    #[error("invalid JSON format")]
    Parse,

    #[error("key not found: {0}")]
    KeyNotFound(String),
}

fn main() {
    assert_eq!(ConfigError::Read.to_string(), "failed to read configuration");
}
```

`JSON` remains uppercase because it is an acronym; the sentence itself still starts with the ordinary lowercase word `invalid`.

## Standard-Library Convention

The standard library documents this convention directly. One representative example is `ParseIntError`:

```rust
fn main() {
    let error = "NaN".parse::<u32>().unwrap_err();
    assert_eq!(error.to_string(), "invalid digit found in string");
}
```

The exact text of platform-originating I/O errors is not a good style oracle for your own API: some messages ultimately come from the operating system. Follow the `Error` display convention for messages your type controls.

## Do Not Duplicate the Source in `Display`

When an outer error exposes an inner error through `Error::source()`, its own display should normally describe the outer failure rather than print the source again:

```rust
use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
#[error("failed to read configuration")]
struct ConfigReadError {
    #[source]
    source: io::Error,
}

fn main() {
    let error = ConfigReadError {
        source: io::Error::new(io::ErrorKind::NotFound, "config file missing"),
    };
    assert_eq!(error.to_string(), "failed to read configuration");
}
```

A reporting layer can render the source chain. If the outer `Display` also embeds `{source}`, a chain-aware reporter may show the same cause twice.

There are APIs where including source text in the outer display is intentional, especially when the type does not expose it as `source()`. Make that decision deliberately.

## Formatting Guidelines

| Prefer | Avoid when composing error chains |
|---|---|
| `failed to parse config` | `Failed to parse config.` |
| `invalid input: expected number` | `Invalid input - expected a number!` |
| `connection timed out after {seconds}s` | `Connection Timed Out After {seconds} seconds.` |
| `key {key:?} not found` | `Key Not Found: {key}` |

The point is composability and consistency, not blindly lowercasing every token.

## Capitalization Exceptions

Messages may legitimately begin with a token whose spelling starts uppercase:

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ProtocolError {
    #[error("HTTP request failed")]
    Http,

    #[error("OAuth token expired")]
    OAuth,

    #[error("E0001: invalid input")]
    Code,
}

fn main() {
    assert_eq!(ProtocolError::Http.to_string(), "HTTP request failed");
}
```

Do not rewrite `HTTP` to `http` or `OAuth` to `oauth` merely to satisfy the lowercase convention.

## Error Values Versus User-Facing Reports

`Display` for an error value is often a fragment designed to compose. A top-level CLI/reporting layer is free to add labels, capitalization, punctuation, color, source snippets, or remediation text around the chain.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
#[error("configuration file is missing")]
struct ConfigMissing;

fn main() {
    let error = ConfigMissing;
    eprintln!("Error: {error}");
}
```

Keeping those presentation concerns at the reporting boundary prevents every low-level error type from baking in terminal-oriented prose.

## Practical Guidance

- Default to concise lowercase phrases without trailing punctuation for error `Display` text.
- Preserve normal spelling for acronyms, proper nouns, identifiers, and codes.
- Describe the current abstraction layer; let `source()` carry the cause chain.
- Avoid rendering the same source both in the outer message and again through a chain-aware reporter unless that duplication is intentional.
- Treat top-level user presentation separately from the composable `Display` text of individual errors.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - Typed error displays
- [err-context-chain](./err-context-chain.md) - Adding operation context
- [err-source-chain](./err-source-chain.md) - Preserving causes
