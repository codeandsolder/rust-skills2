# anti-unwrap-abuse

> Avoid `unwrap()` and `expect()`; make failure handling or invariant representation explicit

## Why It Matters

`unwrap()` and `expect()` turn `None` or `Err` into hidden panic control flow. For strict AI-maintained code, there is little reason to accept that shortcut: propagate failures, handle alternatives, assert on the value directly in tests, or represent the invariant in the type system.

The goal is not merely “no bare unwraps.” Replacing `unwrap()` with `expect()` keeps the same failure semantics and is not a fix.

## Bad

```rust
use std::collections::HashMap;
use std::fs;

fn load_port(path: &str, values: &HashMap<String, String>) -> u16 {
    let config = fs::read_to_string(path).unwrap();
    let port: u16 = config.trim().parse().expect("port should parse");
    let _mode = values.get("mode").unwrap();
    port
}
```

A missing file, bad configuration value, or omitted key is ordinary failure here, not a reason for an implicit panic.

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

## Expected Alternatives

Use the operation that matches the policy instead of panicking:

```rust
use std::collections::HashMap;

let user_input = "not a number";
let num: i32 = user_input.parse().unwrap_or(0);
assert_eq!(num, 0);

let mut map = HashMap::from([("key", 7)]);
if let Some(value) = map.get("key") {
    assert_eq!(*value, 7);
}

assert_eq!(map.remove("missing"), None);
```

For channels, EOF, iterator exhaustion, and normal shutdown, handle the corresponding `Result`/`Option` explicitly.

## Tests Do Not Need Panic Extraction

```rust
#[test]
fn parses_literal() -> Result<(), std::num::ParseIntError> {
    let value: u32 = "42".parse()?;
    assert_eq!(value, 42);
    Ok(())
}
```

When testing an error path, assert on the `Result` directly:

```rust
#[test]
fn rejects_bad_literal() {
    let parsed = "not-a-number".parse::<u32>();
    assert!(parsed.is_err());
}
```

## Prefer Infallible Constants and Constructors

Do not parse a hard-coded value and then `expect()` it when the type already exposes the value directly.

```rust
let loopback = std::net::Ipv4Addr::LOCALHOST;
assert_eq!(loopback.octets(), [127, 0, 0, 1]);
```

For application invariants, validate once and construct a type that stores the validated state.

## Common Alternatives

| Intent | Typical API |
|---|---|
| Propagate an error | `?` |
| Add context / map error | `map_err`, error-context crate |
| Provide an eager default | `unwrap_or` |
| Provide a lazy default | `unwrap_or_else` |
| Convert `Option` to `Result` | `ok_or` / `ok_or_else` |
| Handle both cases locally | `match`, `if let`, `let ... else` |
| Enforce an invariant | validated constructor/newtype/state machine |
| Abort an application intentionally | return error to the top-level runner, log it, return `ExitCode` |

## `unwrap_unchecked()` Is Different and Unsafe

`unwrap_unchecked()` causes undefined behavior if its precondition is false. It is not a substitute for avoiding `unwrap()`; use it only when the invariant is proved and the unsafe operation is justified like any other unsafe block.

```rust
let opt = Some(5_u32);

if opt.is_some() {
    // SAFETY: `is_some()` was checked on the same immutable value above.
    let value = unsafe { opt.unwrap_unchecked() };
    assert_eq!(value, 5);
}
```

Do not assume `unwrap_unchecked()` improves performance. Measure optimized code before replacing a safe branch with unsafe code.

## Clippy

For strict AI development:

```text
-Fclippy::unwrap_used
-Fclippy::expect_used
-Fclippy::panic
```

Use `forbid` in CI so local lint attributes cannot re-enable panic-style extraction.

## See Also

- [err-question-mark](err-question-mark.md) - Use `?` for propagation
- [err-result-over-panic](err-result-over-panic.md) - Return `Result` for failure
- [err-expect-bugs-only](err-expect-bugs-only.md) - Explicit alternatives to `expect()`
