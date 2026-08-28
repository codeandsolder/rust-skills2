# opt-cold-unlikely

> Use `#[cold]` or `core::hint::cold_path()` only when an unlikely path is known or measured to matter.

## Why It Matters

Rust exposes two stable ways to tell the optimizer that code is unlikely:

- `#[cold]` is a **function-level hint** that the function is unlikely to be called.
- `core::hint::cold_path()` is a **path-level hint** that the current branch is unlikely to be taken.

Both are optimization hints, not semantic guarantees. The compiler is free to choose how to use them. Do not promise a particular section layout, branch instruction, inlining decision, or optimization budget merely because one of these hints appears in source.

## Bad: Annotating a Rare-Looking Path by Intuition

<!-- rust-check: compile -->
```rust
#[derive(Debug, PartialEq, Eq)]
enum ValidationError {
    Empty,
    TooLong,
}

fn validate(input: &str) -> Result<usize, ValidationError> {
    // There is no evidence here that either branch matters to performance.
    if input.is_empty() {
        return cold_empty();
    }
    if input.len() > 1_000 {
        return cold_too_long();
    }
    Ok(input.len())
}

#[cold]
fn cold_empty() -> Result<usize, ValidationError> {
    Err(ValidationError::Empty)
}

#[cold]
fn cold_too_long() -> Result<usize, ValidationError> {
    Err(ValidationError::TooLong)
}
```

This compiles, but the attributes are unsupported by evidence. A rare branch is not automatically a performance problem.

## Good: Apply a Hint Where the Cold Split Is Intentional

<!-- rust-check: compile -->
```rust
#[derive(Debug, PartialEq, Eq)]
enum ParseError {
    InvalidDigit(u8),
}

fn parse_digit(byte: u8) -> Result<u8, ParseError> {
    if byte.is_ascii_digit() {
        return Ok(byte - b'0');
    }

    // Stable since Rust 1.95. This marks the current path as cold without
    // requiring an extracted helper function.
    core::hint::cold_path();
    Err(ParseError::InvalidDigit(byte))
}

assert_eq!(parse_digit(b'7'), Ok(7));
```

Use the hint when profiling, code-size inspection, or strong workload knowledge says the distinction is useful. Keep the ordinary branch when the optimizer already produces good code.

## `#[cold]` for Extracted Work

Extracting a substantial rare path can also keep the hot function simpler. `#[cold]` tells the compiler that the helper is unlikely to be called; it does **not** guarantee that the helper is placed in a special section or never inlined.

<!-- rust-check: compile -->
```rust
#[derive(Debug)]
struct ErrorReport {
    message: String,
}

fn process(value: i32) -> Result<i32, ErrorReport> {
    if value >= 0 {
        Ok(value * 2)
    } else {
        negative_error(value)
    }
}

#[cold]
fn negative_error(value: i32) -> Result<i32, ErrorReport> {
    Err(ErrorReport {
        message: format!("negative input: {value}"),
    })
}
```

If code size specifically matters, `#[inline(never)]` can be evaluated separately. Do not mechanically combine it with `#[cold]`; each attribute communicates a different hint and should have a reason.

## `cold_path()` Is the Stable Path Hint

As of Rust 1.98, `core::hint::cold_path()` is stable (since 1.95). The direct `core::hint::likely` and `unlikely` functions are still nightly-only.

That means stable code should not teach `likely()` / `unlikely()` as if they were ordinary stable APIs. In many cases a normal branch plus `cold_path()` in the rare arm is clearer anyway.

<!-- rust-check: compile -->
```rust
fn checked_index(slice: &[u8], index: usize) -> Option<u8> {
    if index >= slice.len() {
        core::hint::cold_path();
        return None;
    }
    Some(slice[index])
}
```

## What the Hints Do Not Guarantee

Do not state these as language guarantees:

- a dedicated `.cold` object-file section,
- a specific hardware branch-prediction instruction,
- that a `#[cold]` function can never inline,
- that the optimizer spends a fixed smaller budget on cold code,
- a performance improvement on every target.

The Rust Reference deliberately describes `#[cold]` as a suggestion that a function is unlikely to be called. `cold_path()` likewise says the compiler **may** optimize non-cold paths at the expense of the cold path.

## Measure the Result

When this is performance-motivated, compare representative release builds. Useful evidence may include:

- application profiles,
- benchmark distributions rather than one noisy run,
- emitted assembly or code-size inspection,
- instruction-cache/front-end counters when available on the target.

Remove the hint if it does not help or makes the code harder to understand.

## See Also

- [opt-inline-never-cold](./opt-inline-never-cold.md) - `inline(never)` and cold code
- [opt-cold-path](./opt-cold-path.md) - Path-level cold hints
- [perf-profile-first](./perf-profile-first.md) - Measure before tuning
