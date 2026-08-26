# anti-unwrap-abuse

> Avoid `unwrap()` for recoverable production errors; reserve panics for proven invariants and bugs

## Why It Matters

`unwrap()` turns `None` or `Err` into a panic. That is appropriate when failure would prove a programmer invariant is broken, but it is poor handling for expected conditions such as missing files, malformed user input, disconnected channels, or absent map keys.

The goal is not “zero unwraps at any cost.” Make the failure policy explicit: propagate recoverable errors, handle expected alternatives, and use `expect`/`unwrap` only where panic is genuinely the intended response.

## Bad

```rust
use std::collections::HashMap;
use std::fs;

fn load_port(path: &str, values: &HashMap<String, String>) -> u16 {
    let config = fs::read_to_string(path).unwrap();
    let port: u16 = config.trim().parse().unwrap();
    let _mode = values.get("mode").unwrap();
    port
}
```

A missing file, bad configuration value, or omitted key is ordinary input failure here, not evidence that Rust program invariants were violated.

## Good

```rust
use std::collections::HashMap;
use std::fs;
use std::io;

#[derive(Debug)]
enum ConfigError {
    Io(io::Error),
    InvalidPort(std::num::ParseIntError),
    MissingMode,
}

impl From<io::Error> for ConfigError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<std::num::ParseIntError> for ConfigError {
    fn from(error: std::num::ParseIntError) -> Self {
        Self::InvalidPort(error)
    }
}

fn load_port(
    path: &str,
    values: &HashMap<String, String>,
) -> Result<(u16, String), ConfigError> {
    let config = fs::read_to_string(path)?;
    let port = config.trim().parse()?;
    let mode = values.get("mode").ok_or(ConfigError::MissingMode)?.clone();
    Ok((port, mode))
}
```

The caller can now decide whether to retry, report configuration errors, fall back, or terminate. Returning an owned mode string here keeps the example focused on error policy rather than introducing lifetime relationships between two borrowed inputs.

## Expected Alternatives

Use the operation that matches the policy instead of panicking by default:

```rust
use std::collections::HashMap;

let user_input = "not a number";
let num: i32 = user_input.parse().unwrap_or(0);
assert_eq!(num, 0);

let mut map = HashMap::from([("key", 7)]);
if let Some(value) = map.get("key") {
    assert_eq!(*value, 7);
}

let removed = map.remove("missing");
assert_eq!(removed, None);
```

For channels, EOF, iterator exhaustion, and similar control flow, handle the corresponding `Result`/`Option` rather than calling `unwrap` and converting normal shutdown into a panic.

## When `unwrap()` / `expect()` Can Be Appropriate

```rust
// Tests: a panic is an ordinary test failure.
#[test]
fn parses_literal() {
    let value: u32 = "42".parse().unwrap();
    assert_eq!(value, 42);
}

// A source-code literal whose validity is part of the program itself.
let loopback: std::net::IpAddr = "127.0.0.1"
    .parse()
    .expect("hard-coded loopback address is valid");

// After construction establishes an invariant locally.
let mut values = vec![1, 2, 3];
if !values.is_empty() {
    let last = values.pop().expect("checked non-empty immediately above");
    assert_eq!(last, 3);
}
```

Prefer `expect("reason")` over a bare `unwrap()` when the invariant is not self-evident. The message should explain **why failure is impossible**, not merely restate the operation.

## Common Alternatives

| Intent | Typical API |
|--------|-------------|
| Propagate an error | `?` |
| Add context / map error | `map_err`, error-context crate |
| Provide an eager default | `unwrap_or` |
| Provide a lazy default | `unwrap_or_else` |
| Convert `Option` to `Result` | `ok_or` / `ok_or_else` |
| Handle both cases locally | `match`, `if let`, `let ... else` |
| Assert a true program invariant | `expect` / `unwrap` with justification |

## `unwrap_unchecked()` Is a Separate Unsafe Operation

`unwrap_unchecked()` is unsafe because calling it on `None`/`Err` is undefined behavior, not a panic. It should only appear when the invariant is proved and the unsafe operation is justified like any other unsafe code.

```rust
let opt = Some(5u32);

if opt.is_some() {
    // SAFETY: `is_some()` was checked on the same value and it cannot change.
    let value = unsafe { opt.unwrap_unchecked() };
    assert_eq!(value, 5);
}
```

Do not assume `unwrap_unchecked()` improves performance. Measure optimized code before replacing a safe invariant check with unsafe code.

## Clippy

```rust
#![warn(clippy::unwrap_used)]
```

This can be useful as a review aid in production modules. Scope exceptions where panic is intentional rather than weakening the lint globally.

## See Also

- [err-question-mark](err-question-mark.md) - Use `?` for propagation
- [err-result-over-panic](err-result-over-panic.md) - Return `Result` for recoverable failures
- [err-expect-bugs-only](err-expect-bugs-only.md) - Reserve `expect` for invariants
