# err-expect-bugs-only

> Use `expect()` when failure violates a justified assumption; return or handle errors for anticipated runtime failures

## Why It Matters

`expect()` turns `None` or `Err` into a panic. That is appropriate when the program has a well-founded reason the value **should** be present or successful and failure indicates a broken invariant, violated startup assumption, or test expectation.

It is a poor substitute for error handling when failure is an ordinary possibility: user input can be invalid, files can be absent, networks can fail, and remote data can be malformed.

The distinction is about the contract and recovery model, not whether the code happens to be in a library or binary.

## Bad: Panic on Anticipated Failures

```rust
use std::fs;

fn parse_port(input: &str) -> u16 {
    input.parse().expect("port should parse")
}

fn load_optional_config(path: &str) -> String {
    fs::read_to_string(path).expect("config should exist")
}

fn main() {}
```

If `input` comes from a user or `path` names an optional/external file, those failures are normal runtime outcomes and should be represented explicitly.

## Good: Return the Anticipated Failure

```rust
use std::fs;
use std::io;
use std::num::ParseIntError;

fn parse_port(input: &str) -> Result<u16, ParseIntError> {
    input.parse()
}

fn load_optional_config(path: &str) -> Result<String, io::Error> {
    fs::read_to_string(path)
}

fn main() {}
```

## Good: `expect()` for a Source-Code Invariant

A hard-coded regular expression that has already been reviewed as source code is a reasonable place for `expect()`:

```rust
use regex::Regex;

fn date_regex() -> Regex {
    Regex::new(r"^\d{4}-\d{2}-\d{2}$")
        .expect("hard-coded date regex should be valid")
}

fn main() {
    assert!(date_regex().is_match("2026-08-27"));
}
```

If this panics, changing runtime input cannot fix it; the source code itself contains an invalid regex.

## Good: `expect()` After an Explicit Invariant Check

```rust
fn first_after_nonempty_check(values: &[u32]) -> u32 {
    assert!(!values.is_empty(), "caller must provide at least one value");
    *values
        .first()
        .expect("slice should be nonempty after the assertion above")
}

fn main() {
    assert_eq!(first_after_nonempty_check(&[7, 8]), 7);
}
```

This example is slightly redundant—the indexing operation could express the same invariant—but it demonstrates the important point: the message explains **why** `Some` is expected.

## Recommended Message Style

The standard library recommends phrasing `expect` messages around the reason the value **should** be `Some` or `Ok`.

```rust
fn extension(path: &std::path::Path) -> &std::ffi::OsStr {
    path.extension()
        .expect("validated input path should have an extension")
}

fn main() {}
```

Prefer messages such as:

```text
validated input path should have an extension
hard-coded regex should be valid
queue should contain the item inserted immediately above
wrapper script should set IMPORTANT_PATH
```

A `BUG:` prefix can be a useful project convention for internal invariants, but it is **not** a Rust requirement and should not replace explaining the assumption.

Avoid messages that merely repeat the symptom:

```text
failed
unexpected None
invalid state
unwrap failed
```

Those say what happened, not why success was expected.

## Startup Assumptions Are a Policy Choice

A binary may reasonably decide that some missing prerequisite makes startup impossible:

```rust
fn required_home() -> String {
    std::env::var("HOME")
        .expect("HOME should be set in the supported runtime environment")
}

fn main() {
    let _ = required_home();
}
```

That does not make missing environment variables universally “bugs.” A CLI that can produce a friendly diagnostic may prefer returning an error instead. Use `expect()` when panic is the intended response to violation of the assumption.

## Tests and Examples

`unwrap()` and `expect()` are often fine in tests when the test itself asserts that setup or an operation succeeds:

```rust
#[test]
fn parses_valid_port() {
    let port: u16 = "8080".parse().expect("test fixture should be a valid port");
    assert_eq!(port, 8080);
}

fn main() {}
```

A useful `expect` message can still make a failing test easier to diagnose.

## Linting Policy

Clippy's `expect_used` and `unwrap_used` lints are restriction lints. Projects that deny them can make narrow exceptions where an invariant is genuinely clearer with `expect()`:

```rust
#[expect(clippy::expect_used, reason = "hard-coded regex is a source invariant")]
fn parser() -> regex::Regex {
    regex::Regex::new(r"^[a-z]+$")
        .expect("hard-coded parser regex should be valid")
}

fn main() {}
```

Use the lint policy to force justification, not to pretend every panic conversion is equally harmful.

## Decision Guide

| Failure means | Usually prefer |
|---|---|
| invalid user/request input | `Result`, validation, or explicit handling |
| missing/failed external resource | `Result` or fallback |
| network/service failure | `Result`, retry, or fallback |
| violated internal invariant | panic / `expect()` can be appropriate |
| invalid hard-coded source data | `expect()` can be appropriate |
| unsupported startup environment | application policy: diagnostic or `expect()` |
| test fixture unexpectedly invalid | `expect()` / `unwrap()` is usually fine |

## Practical Guidance

- Before writing `expect()`, state why success is guaranteed or intentionally assumed.
- Phrase the message around that expectation, commonly with “should.”
- Do not use `expect()` to erase ordinary user, I/O, network, or parsing failures.
- A `BUG:` prefix is optional house style, not the substance of a good message.
- If callers can meaningfully recover, preserve the failure as `Result` instead of panicking.

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoiding unjustified unwraps
- [err-expect-not-allow](./err-expect-not-allow.md) - Using lint expectations deliberately
- [err-result-over-panic](./err-result-over-panic.md) - Choosing `Result` versus panic
- [api-parse-dont-validate](./api-parse-dont-validate.md) - Type-driven validation
