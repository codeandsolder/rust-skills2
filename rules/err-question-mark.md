# err-question-mark

> Use `?` when a fallible operation should short-circuit through the surrounding error context

## Why It Matters

The `?` operator is Rust's concise syntax for propagating a failure from a compatible return context. For `Result<T, E>`, an `Ok(value)` yields `value`, while an `Err(error)` returns from the surrounding context, converting the error with `From` when needed. `?` also has defined behavior for `Option` and several other standard-library try-like types.

Use it when propagation is the intended control flow. It is not a replacement for handling an error locally, adding context, retrying, or intentionally panicking on an invariant violation.

## Bad

```rust
use std::{fs, io};

fn read_config(path: &str) -> Result<String, io::Error> {
    match fs::read_to_string(path) {
        Ok(contents) => Ok(contents),
        Err(error) => Err(error),
    }
}

fn main() {}
```

The explicit match adds no behavior; it merely re-spells propagation.

## Good

```rust
use std::{fs, io, num::ParseIntError};

#[derive(Debug)]
enum LoadError {
    Io(io::Error),
    InvalidPort(ParseIntError),
}

impl From<io::Error> for LoadError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<ParseIntError> for LoadError {
    fn from(error: ParseIntError) -> Self {
        Self::InvalidPort(error)
    }
}

fn load_port(path: &str) -> Result<u16, LoadError> {
    let text = fs::read_to_string(path)?;
    let port = text.trim().parse::<u16>()?;
    Ok(port)
}

fn main() {}
```

Each `?` propagates to `load_port`'s `Result`. The two `From` implementations define the permitted error conversions.

## For `Result`, Think in Terms of Behavior

For a `Result<T, E>`, this:

```rust
fn parse_number(input: &str) -> Result<i32, std::num::ParseIntError> {
    let value = input.parse::<i32>()?;
    Ok(value)
}

fn main() {}
```

has the same relevant behavior as explicitly matching the result and returning its error. Do not teach a universal source-level expansion of `?`: the language also supports `Option`, `ControlFlow`, and other specified forms, and the underlying `Try`/`FromResidual` traits remain unstable library APIs.

## `?` with `Option`

```rust
fn first_word(text: &str) -> Option<&str> {
    let first_line = text.lines().next()?;
    let first_word = first_line.split_whitespace().next()?;
    Some(first_word)
}

fn main() {
    assert_eq!(first_word("hello world"), Some("hello"));
    assert_eq!(first_word(""), None);
}
```

An `Option` `?` propagates `None`; it does not automatically convert `None` into a `Result` error. Convert explicitly when that is the contract:

```rust
#[derive(Debug, PartialEq, Eq)]
struct MissingPort;

fn required_port(port: Option<u16>) -> Result<u16, MissingPort> {
    port.ok_or(MissingPort)
}

fn main() {
    assert_eq!(required_port(Some(8080)), Ok(8080));
    assert_eq!(required_port(None), Err(MissingPort));
}
```

## Add Context Before Propagating When Needed

`?` preserves/converts an error; it does not invent application context. Add context at the boundary where it becomes meaningful.

```rust
use std::fs;

fn read_named(path: &str) -> Result<String, String> {
    let contents = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {path}: {error}"))?;
    Ok(contents)
}

fn main() {}
```

Application error crates such as `anyhow` provide richer context helpers; library code often uses a structured error enum instead.

## In `main`

`main` may return a type implementing `Termination`, so returning `Result` is a simple way to use `?` in small programs:

```rust
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let _contents = std::fs::read_to_string("config.toml")?;
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    run()?;
    Ok(())
}
```

For an application that needs custom logging, exit codes, retries, or cleanup, handle the top-level error explicitly instead.

## Do Not Duplicate Nightly or Diagnostic Guidance Here

Try blocks are still nightly-only; see [err-try-block-experimental](./err-try-block-experimental.md). Diagnostic shaping with `#[diagnostic::do_not_recommend]` is a separate trait-impl concern; see [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md).

## See Also

- [err-context-chain](./err-context-chain.md) - Add error context
- [err-from-impl](./err-from-impl.md) - `From` conversions used by `Result` propagation
- [err-try-block-experimental](./err-try-block-experimental.md) - Experimental try blocks
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) - Diagnostic hints for trait impls
- [err-anyhow-app](./err-anyhow-app.md) - Application error handling
