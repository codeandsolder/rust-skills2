# doc-question-mark

> Give doctests a `Result`-returning context when demonstrating fallible operations; do not hide setup failure with unwrap/expect

## Why It Matters

Documentation examples are copied. If examples use `unwrap()` or `expect()`, agents and users reproduce panic-style extraction even when the API naturally supports propagation.

Rustdoc does **not** simply make every doctest return `Result` when it sees `?`. Give the example an explicit `Result`-returning `main`, or end the doctest with a hidden, type-annotated `Ok::<(), E>(())` so rustdoc can use its implicit result wrapper.

## Bad

```rust
/// Reads a configuration file.
///
/// # Examples
///
/// ```no_run
/// let config = std::fs::read_to_string("config.toml").unwrap();
/// println!("{} bytes", config.len());
/// ```
fn read_config_bad() {}
```

The example teaches panic on ordinary I/O failure.

## Good

```rust
use std::{fs, io, path::Path};

/// Reads a configuration file.
///
/// # Errors
///
/// Returns the I/O error produced while reading `path`.
///
/// # Examples
///
/// ```no_run
/// # use std::io;
/// # fn main() -> io::Result<()> {
/// let config = std::fs::read_to_string("config.toml")?;
/// println!("{} bytes", config.len());
/// # Ok(())
/// # }
/// ```
pub fn read_config(path: &Path) -> io::Result<String> {
    fs::read_to_string(path)
}

fn main() {}
```

The hidden `main` keeps the rendered example focused while preserving real failure semantics.

## Implicit Result Wrapper

Rustdoc can recognize a doctest whose final hidden expression disambiguates the error type:

```rust
/// ```no_run
/// use std::io;
/// let mut input = String::new();
/// io::stdin().read_line(&mut input)?;
/// # Ok::<(), io::Error>(())
/// ```
fn reads_stdin() {}

fn main() {}
```

This is a rustdoc preprocessing convention, not ordinary Rust source syntax.

## Async Doctests

There is no built-in async `main` in stable Rust. Put asynchronous `?` use inside a hidden async function/block appropriate to the runtime your crate documents, and use `no_run` when the example should only compile.

```rust
/// ```no_run
/// # use std::io;
/// # async fn example() -> io::Result<()> {
/// let contents = async { std::fs::read_to_string("config.toml") }.await?;
/// println!("{} bytes", contents.len());
/// # Ok(())
/// # }
/// ```
fn async_example_docs() {}

fn main() {}
```

For Tokio or another runtime, use that crate's normal hidden setup rather than adding a synchronous panic extraction merely to make the snippet shorter.

## Fixed Values Do Not Need Panic Extraction Either

When the lesson uses a fixed value, prefer an infallible constructor/constant or assert on the fallible result directly.

```rust
fn main() {
    assert_eq!("42".parse::<i32>(), Ok(42));
    assert_eq!(std::net::Ipv4Addr::LOCALHOST.octets(), [127, 0, 0, 1]);
}
```

Documentation should follow the same no-unwrap/no-expect policy as production and test source.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hiding setup code
- [err-question-mark](./err-question-mark.md) - Error propagation
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest behavior
