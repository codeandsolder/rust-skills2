# err-result-over-panic

> Use `Result<T, E>` for fallible operations; encode invariants explicitly and keep deliberate termination at the application boundary

## Why It Matters

`Result` makes failure part of the function's contract. Callers can inspect, propagate, retry, substitute a fallback, report, or deliberately terminate.

Panic is appropriate for assertion-style contracts and failures inside code that already has panic semantics, but it should not be the default transport for ordinary errors or a hidden substitute for invariant modeling. In particular, `unwrap()`/`expect()` make panic paths easy to add and hard to audit.

## Bad: Panic on Runtime Failure

```rust
fn parse_port(input: &str) -> u16 {
    input.parse().expect("port should parse")
}

fn read_user_file(path: &str) -> String {
    std::fs::read_to_string(path).expect("user file should exist")
}

fn main() {}
```

## Good: Return the Failure

```rust
use std::io;
use std::num::ParseIntError;

fn parse_port(input: &str) -> Result<u16, ParseIntError> {
    input.parse()
}

fn read_user_file(path: &str) -> Result<String, io::Error> {
    std::fs::read_to_string(path)
}

fn main() {}
```

## Typed Application Example

```rust
use serde_json::Value;
use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("failed to read config")]
    Io(#[from] io::Error),

    #[error("invalid config JSON")]
    Parse(#[from] serde_json::Error),
}

fn parse_config(path: &str) -> Result<Value, ConfigError> {
    let text = std::fs::read_to_string(path)?;
    Ok(serde_json::from_str(&text)?)
}

fn main() {}
```

The specific error crate is incidental; the important property is that the failure remains representable in the return type.

## Encode Invariants Without Re-Looking-Up Fallibly

When an operation itself can produce the desired reference, use that API rather than inserting and then `expect()`-ing a second lookup.

```rust
use std::collections::HashMap;

fn inserted_value(
    map: &mut HashMap<String, u32>,
    key: String,
    value: u32,
) -> &mut u32 {
    map.entry(key).or_insert(value)
}

fn main() {
    let mut map = HashMap::new();
    assert_eq!(*inserted_value(&mut map, "x".into(), 7), 7);
}
```

More generally, validate once and construct a type/state that directly carries the guarantee.

## Documented Caller Contracts May Assert

Some APIs intentionally panic when callers violate a documented precondition. Slice indexing is the standard example.

For your own public API, decide deliberately whether invalid input is:

- an anticipated condition represented by `Result`/`Option`, or
- a caller contract violation enforced by an assertion/indexing operation.

If a public function can panic under ordinary-looking inputs, document the condition in a `# Panics` section. This is not a reason to use `expect()` for internal extraction.

## Startup Failures Belong at the Application Boundary

```rust
use std::process::ExitCode;

fn run() -> Result<(), std::env::VarError> {
    let _root = std::env::var("APP_ROOT")?;
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("fatal: APP_ROOT is unavailable: {error}");
            ExitCode::FAILURE
        }
    }
}
```

“The program cannot continue” does not require a hidden panic.

## `catch_unwind` Is a Boundary Tool, Not Normal Error Handling

```rust
use std::panic::{catch_unwind, AssertUnwindSafe};

fn run_plugin_boundary(mut callback: impl FnMut()) -> bool {
    catch_unwind(AssertUnwindSafe(|| callback())).is_ok()
}

fn main() {}
```

Use panic isolation at FFI/framework/plugin boundaries where unwinding already exists. Do not convert routine file/network/validation errors into panics just to catch them later.

## Tests

Tests can return `Result` and use `?` for setup:

```rust
#[test]
fn parses_port() -> Result<(), std::num::ParseIntError> {
    let port: u16 = "8080".parse()?;
    assert_eq!(port, 8080);
    Ok(())
}
```

Assertions remain the test harness's normal failure mechanism.

## Decision Guide

| Situation | Usually prefer |
|---|---|
| invalid user/request input | `Result` / validation |
| file, network, service, or parse failure | `Result` |
| optional absence | `Option` or `Result`, depending on semantics |
| internal invariant | encode in type/state; otherwise explicit invariant error |
| caller violates documented precondition | documented assertion/indexing contract |
| test fixture/setup unexpectedly fails | test returns `Result` and uses `?` |
| boundary must contain third-party unwinding | `catch_unwind` when panic strategy permits |
| application cannot start | diagnostic + failure `ExitCode` at outer boundary |

## Practical Guidance

- Model fallible operations as return values.
- Do not use `unwrap()`/`expect()` as invariant shorthand.
- Keep process termination policy in the top-level runner.
- Do not use `catch_unwind` as routine error control flow.
- Document intentional public panic contracts.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - Typed errors
- [err-anyhow-app](./err-anyhow-app.md) - Application error reports
- [err-expect-bugs-only](./err-expect-bugs-only.md) - Explicit alternatives to `expect()`
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoid panic-style extraction
