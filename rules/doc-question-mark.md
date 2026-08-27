# doc-question-mark

> Give doctests a `Result`-returning context when demonstrating `?`

## Why It Matters

Documentation examples should model the error-handling behavior callers are expected to use. When an operation should propagate an error, `?` is usually clearer than an unconditional `.unwrap()`.

Rustdoc does **not** simply make every doctest return `Result` when it sees `?`. Ordinary snippets are normally wrapped in `fn main() { ... }`, so a bare `?` would fail. Give the example an explicit `Result`-returning `main`, or end the doctest with a hidden, type-annotated `Ok::<(), E>(())` so rustdoc can use its implicit `Result` wrapper.

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

The example panics on an ordinary I/O failure even though propagation is the behavior being taught.

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

The hidden `main` makes the propagation context explicit while keeping boilerplate out of the rendered example.

## Implicit Result Wrapper

Since Rust 1.34, rustdoc can also recognize a doctest whose final hidden expression disambiguates the error type:

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

This is a rustdoc preprocessing convention, not ordinary Rust source syntax. In particular, the final `(())` form is significant to rustdoc's recognition of the implicit `Result`-returning wrapper.

## Async Doctests

There is no built-in async `main` in stable Rust. Put asynchronous `?` use inside a hidden async function or block appropriate to the runtime your crate documents, and use `no_run` when the example should only be compiled.

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

For a Tokio API, for example, the hidden setup can use the runtime pattern the crate already expects; do not invent a synchronous `.unwrap()` merely to avoid showing setup.

## When `.unwrap()` or `.expect()` Is Fine

A documentation example may intentionally use `.unwrap()` or `.expect()` when panic-on-failure is irrelevant to the lesson and the input is a fixed invariant, such as parsing a known-valid literal. Do not mechanically replace every unwrap with `?`.

```rust
fn main() {
    let n: i32 = "42".parse().expect("literal is valid");
    assert_eq!(n, 42);
}
```

Use `?` when propagation is part of the API pattern being demonstrated; use an assertion or explicit panic when failure would indicate that the example itself is wrong.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hiding setup code
- [err-question-mark](./err-question-mark.md) - Error propagation
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest behavior
