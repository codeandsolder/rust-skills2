# anti-panic-expected

> Do not use panics as the API for expected runtime failures

## Why It Matters

A panic signals that normal execution cannot continue under the function's assumptions. Depending on the panic strategy and boundary, it may unwind the current thread or abort the process. That makes panic a poor substitute for `Result` or `Option` when callers are expected to encounter and handle a condition such as invalid input, missing files, parse failures, or unavailable resources.

Use typed return values for ordinary failure. Reserve panic for violated internal invariants, programmer errors, assertions, and deliberate top-level policies where recovery is not part of the contract.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;

fn parse_age(input: &str) -> u32 {
    // Invalid external input is expected, but this turns it into a panic.
    input.parse().expect("invalid age")
}

fn load_settings() -> String {
    // Missing files and I/O failures are environmental conditions.
    fs::read_to_string("settings.txt").expect("settings file missing")
}

fn validate_age(age: i32) {
    // Domain validation failure should normally be represented in the API.
    if age < 0 {
        panic!("age cannot be negative");
    }
}
```

The issue is not that these panics are guaranteed to kill the whole process. The issue is that ordinary runtime conditions escape through the panic mechanism rather than the function's normal return contract.

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

Now the caller decides whether to retry, use a default, translate the error, display it, terminate the program, or take another recovery action.

## Panic for Internal Invariants

Panicking is appropriate when continuing would mean the program's own assumptions have already been violated:

```rust
struct CheckedBuffer {
    data: Vec<u8>,
}

impl CheckedBuffer {
    fn byte_after_validation(&self, index: usize) -> u8 {
        assert!(
            index < self.data.len(),
            "validated index must remain in bounds"
        );
        self.data[index]
    }
}
```

If the index came directly from untrusted input and out-of-range values are normal, returning `Option<u8>` or `Result<_, _>` would be the better API instead.

## Library Boundary Versus Binary Policy

A library generally should not decide that an environmental startup failure is unrecoverable for every caller:

```rust
use std::fs;
use std::io;

pub fn load_required_template(path: &str) -> Result<String, io::Error> {
    fs::read_to_string(path)
}
```

A binary can then deliberately choose a fatal policy at its outer boundary:

```rust
fn start_application() {
    let template = load_required_template("template.txt")
        .expect("application requires template.txt to start");
    let _ = template;
}
```

This preserves composition: reusable code reports the error, while the application decides whether the error is fatal.

## Panic Is Not Ordinary Control Flow

`catch_unwind` exists for unwind boundaries, but it is not a replacement for a normal error-returning API. It only catches unwinding panics, requires unwind-safety considerations, and cannot make an aborting panic strategy recoverable.

```rust
use std::panic;

fn plugin_boundary() -> bool {
    let result = panic::catch_unwind(|| {
        // Third-party callback boundary where panic isolation is deliberate.
        42
    });

    result.is_ok()
}
```

Use such boundaries for panic isolation, not to encode routine “not found” or validation outcomes.

## Tests and Assertions

Tests commonly panic to signal failure because the test harness treats panic as the failure channel:

```rust
#[test]
fn arithmetic_invariant() {
    assert_eq!(2 + 2, 4);
}
```

That does not imply production APIs should use panic for expected domain errors.

## Avoid Panic-Based Lookup APIs When Missing Is Normal

```rust
#[derive(Debug)]
struct Item {
    id: u64,
}

// Bad shape when a missing ID is an expected query result.
fn find_or_panic(items: &[Item], id: u64) -> &Item {
    items
        .iter()
        .find(|item| item.id == id)
        .expect("item must exist")
}

// Better contract for an ordinary lookup.
fn find(items: &[Item], id: u64) -> Option<&Item> {
    items.iter().find(|item| item.id == id)
}
```

If a particular caller has already established that the item must exist, that caller can apply `expect()` at the invariant boundary.

## Decision Guide

| Condition | Typical action |
|-----------|----------------|
| Invalid user/config input | Return `Err` |
| Network/I/O/resource failure | Return `Err` or recover |
| Optional lookup miss | `Option` or domain `Result` |
| Violated internal invariant | `panic!`, `assert!`, or `expect()` may be appropriate |
| Test assertion failure | Panic through the test harness |
| Fatal binary startup policy | Handle `Result` at the outer boundary, possibly with `expect()`/exit |
| Library startup/configuration failure | Usually return the error to the caller |

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — `Result` for expected failure
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Panic-style extraction
- [err-expect-bugs-only](./err-expect-bugs-only.md) — Invariant-oriented `expect()`
