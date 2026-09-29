# anti-panic-expected

> Do not use panics as the API for expected runtime failures; keep deliberate termination and assertions explicit at their real boundary

## Why It Matters

A panic bypasses the function's ordinary return contract. That makes it a poor substitute for `Result` or `Option` when callers can encounter invalid input, missing files, parse failures, unavailable resources, or startup prerequisites.

For strict AI-maintained code, also avoid hiding programmer assumptions behind `unwrap()`/`expect()`. Encode invariants in types where possible and return an explicit invariant error otherwise.

Assertions remain appropriate when an API deliberately documents a caller precondition or a test is asserting behavior; that is different from using panic as routine error transport.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;

fn parse_age(input: &str) -> u32 {
    input.parse().expect("invalid age")
}

fn load_settings() -> String {
    fs::read_to_string("settings.txt").expect("settings file missing")
}

fn validate_age(age: i32) {
    if age < 0 {
        panic!("age cannot be negative");
    }
}
```

All three conditions can be represented in the normal API.

## Good

<!-- rust-check: compile -->
```rust
use std::fs;
use std::io;
use std::num::ParseIntError;

#[derive(Debug, PartialEq)]
enum ValidationError {
    NegativeAge,
}

fn parse_age(input: &str) -> Result<u32, ParseIntError> {
    input.parse()
}

fn load_settings() -> Result<String, io::Error> {
    fs::read_to_string("settings.txt")
}

fn validate_age(age: i32) -> Result<(), ValidationError> {
    if age < 0 {
        Err(ValidationError::NegativeAge)
    } else {
        Ok(())
    }
}
```

## Internal Invariants: Prefer Representation Over Recovery

If construction validates an index, store a representation that cannot become out of bounds, or keep the fallibility in the operation.

```rust
struct CheckedBuffer {
    data: Vec<u8>,
}

impl CheckedBuffer {
    fn byte(&self, index: usize) -> Option<u8> {
        self.data.get(index).copied()
    }
}
```

When an API intentionally has a documented panic contract, such as indexing semantics, use an assertion or the underlying indexing operation and document the `# Panics` condition. Do not use `expect()` merely because the condition is believed impossible.

## Library Boundary Versus Binary Policy

Reusable code reports environmental failure:

```rust
use std::fs;
use std::io;

pub fn load_required_template(path: &str) -> Result<String, io::Error> {
    fs::read_to_string(path)
}
```

The binary chooses whether that error is fatal at its outer boundary:

```rust
use std::process::ExitCode;

fn run() -> Result<(), std::io::Error> {
    let _template = load_required_template("template.txt")?;
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("fatal: {error}");
            ExitCode::FAILURE
        }
    }
}
```

This preserves cleanup and makes termination policy obvious.

## Panic Is Not Ordinary Control Flow

`catch_unwind` is a boundary tool for isolating code that may already panic; it is not a reason to turn normal errors into panics.

```rust
use std::panic;

fn plugin_boundary() -> bool {
    panic::catch_unwind(|| 42).is_ok()
}
```

It only catches unwinding panics and does not make `panic = "abort"` recoverable.

## Tests and Assertions

Tests use assertions as their normal failure channel:

```rust
#[test]
fn arithmetic_invariant() {
    assert_eq!(2 + 2, 4);
}
```

Test setup that is itself fallible can return `Result` and use `?` rather than `unwrap()`/`expect()`.

## Avoid Panic-Based Lookup APIs When Missing Is Normal

```rust
#[derive(Debug)]
struct Item {
    id: u64,
}

fn find(items: &[Item], id: u64) -> Option<&Item> {
    items.iter().find(|item| item.id == id)
}
```

If another layer has stronger knowledge, model that knowledge there instead of converting the lookup to a hidden panic.

## Decision Guide

| Condition | Typical action |
|---|---|
| Invalid user/config input | return `Err` |
| Network/I/O/resource failure | return `Err` or recover |
| Optional lookup miss | `Option` or domain `Result` |
| Internal invariant | encode it in types/state or return explicit invariant error |
| Documented caller precondition | assertion/indexing plus `# Panics` documentation when that contract is intentional |
| Test assertion failure | assertion through the test harness |
| Fatal binary startup policy | handle the `Result` at the outer boundary and return failure `ExitCode` |
| Library startup/configuration failure | return the error to the caller |

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — `Result` for failure
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Panic-style extraction
- [err-expect-bugs-only](./err-expect-bugs-only.md) — Explicit alternatives to `expect()`
