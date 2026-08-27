# err-result-over-panic

> Use `Result<T, E>` for anticipated runtime failure; use panic for violated assumptions, bugs, and APIs whose documented contract chooses to panic

## Why It Matters

Rust has two complementary failure mechanisms:

- `Result` represents anticipated runtime failures that callers may propagate, inspect, retry, replace with a fallback, or report.
- panic represents a failure of an assumption or contract where ordinary return-based recovery is not the API being offered.

A panic is **not literally uncatchable**: with the unwinding panic strategy, `catch_unwind` can establish an unwind boundary. But panic catching is not Rust's general-purpose replacement for `Result`, and with `panic = "abort"` the process aborts instead of unwinding.

## Bad: Panic on Ordinary Runtime Failures

```rust
fn parse_port(input: &str) -> u16 {
    input.parse().expect("port should parse")
}

fn read_user_file(path: &str) -> String {
    std::fs::read_to_string(path).expect("user file should exist")
}

fn main() {}
```

If `input` is user-controlled or the file is external state, parse and I/O failure are ordinary outcomes. Panicking prevents the caller from selecting its own policy.

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

A caller can now propagate, retry, fall back, or convert the error.

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

The important property is not the specific error crate; it is that an expected I/O/parse failure remains representable in the return type.

## Panic for a Violated Internal Invariant

```rust
use std::collections::HashMap;

fn inserted_value<'a>(
    map: &'a mut HashMap<String, u32>,
    key: String,
    value: u32,
) -> &'a u32 {
    map.insert(key.clone(), value);
    map.get(&key)
        .expect("key should exist immediately after insertion")
}

fn main() {
    let mut map = HashMap::new();
    assert_eq!(*inserted_value(&mut map, "x".into(), 7), 7);
}
```

If this assumption fails, the implementation is broken; changing user input is not the recovery path.

## Documented Caller Contracts May Panic

Libraries are not required to eliminate every panic. Many Rust APIs panic when a caller violates a documented precondition. Indexing a slice out of bounds is the obvious standard example.

For your own public API, decide deliberately whether an invalid argument is:

- an anticipated condition represented by `Result`/`Option`, or
- a contract violation for which the API documents a panic.

If a public function can panic under ordinary-looking inputs, document the condition in a `# Panics` section.

## Startup Failures Are an Application Policy Choice

A binary with no useful degraded mode may choose to stop immediately when a required prerequisite is absent:

```rust
fn required_runtime_root() -> String {
    std::env::var("APP_ROOT")
        .expect("APP_ROOT should be set by the service launcher")
}

fn main() {
    let _ = required_runtime_root();
}
```

That can be acceptable, but returning an error from `main` or printing a structured diagnostic is often friendlier. “The program cannot continue” does not by itself require a panic.

## `catch_unwind` Is a Boundary Tool, Not Normal Error Handling

```rust
use std::panic::{catch_unwind, AssertUnwindSafe};

fn run_plugin_boundary(mut callback: impl FnMut()) -> bool {
    catch_unwind(AssertUnwindSafe(|| callback())).is_ok()
}

fn main() {}
```

`catch_unwind` is useful at isolation/FFI/framework boundaries where unwinding must be contained. It only catches unwinding panics, not aborting panics, and `AssertUnwindSafe` is a correctness assertion that deserves review.

Do not convert routine file/network/validation errors into panics merely so they can be caught later.

## Rust 1.92+: Backtraces with `panic = "abort"` on Linux

Rust 1.92 changed Linux code generation so unwind tables are emitted by default even with `-Cpanic=abort`. That restored the ability to produce stack backtraces for aborting panics on Linux without separately forcing unwind tables.

```toml
[profile.release]
panic = "abort"
```

A panic hook can capture a backtrace before the abort:

```rust
use std::backtrace::Backtrace;

fn install_hook() {
    std::panic::set_hook(Box::new(|info| {
        let backtrace = Backtrace::force_capture();
        eprintln!("panic: {info}\nbacktrace:\n{backtrace}");
    }));
}

fn main() {
    install_hook();
}
```

If those unwind tables are unwanted, `-Cforce-unwind-tables=no` can explicitly disable them. This backtrace improvement does **not** make `catch_unwind` work with `panic = "abort"`; no Rust panic unwinding occurs in that mode.

## Rust 1.96: Better Pattern Assertions in Tests

`assert_matches!` stabilized in Rust 1.96 and is preferable to `assert!(matches!(...))` when the failing value's debug representation would help:

```rust
#[derive(Debug)]
enum ParseError {
    Syntax,
}

fn parse(_: &str) -> Result<(), ParseError> {
    Err(ParseError::Syntax)
}

#[test]
fn reports_syntax_error() {
    assert_matches!(parse("bad"), Err(ParseError::Syntax));
}

fn main() {}
```

This is test ergonomics, not a reason to choose panic over `Result` in the production API.

## Do Not Invent an `AssertUnwindSafe` Migration

Rust 1.96 added `From<T> for AssertUnwindSafe<T>` for already-`UnwindSafe` values. The tuple-struct constructor `AssertUnwindSafe(value)` existed long before that release. Do not present ordinary `catch_unwind(AssertUnwindSafe(closure))` syntax as newly enabled by the `From` implementation.

## Decision Guide

| Situation | Usually prefer |
|---|---|
| invalid user/request input | `Result` / validation |
| file, network, service, or parse failure | `Result` |
| optional absence | `Option` or `Result`, depending on semantics |
| violated internal invariant | panic / assertion can be appropriate |
| caller violates documented precondition | documented panic can be appropriate |
| test fixture/setup unexpectedly fails | `expect` / `unwrap` is often fine |
| boundary must contain third-party unwinding | `catch_unwind` when panic strategy permits |
| application cannot start | explicit error exit or panic, by application policy |

## Practical Guidance

- Model failures callers can reasonably encounter as return values.
- Reserve panic for broken assumptions/contracts rather than ordinary adverse conditions.
- Do not claim panics are categorically unrecoverable; distinguish unwinding from aborting panic strategies.
- Do not use `catch_unwind` as routine error control flow.
- Document public panic conditions.
- Treat startup panic versus error reporting as an application UX/operations decision.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - Typed errors
- [err-anyhow-app](./err-anyhow-app.md) - Application error reports
- [err-expect-bugs-only](./err-expect-bugs-only.md) - Justified `expect()` usage
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoiding unjustified unwraps
