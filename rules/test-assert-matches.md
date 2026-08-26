# test-assert-matches

> Use `assert_matches!` / `debug_assert_matches!` (Rust 1.96+) for pattern-based assertions

## Why It Matters

Pattern matching on test results is common—checking enum variants, error kinds, or partial data. `assert!(matches!(..))` gives little information about the actual value on failure. `assert_matches!`, stabilized in Rust 1.96, prints the debug representation of the value that failed to match.

Import the macros explicitly when needed with `use std::{assert_matches, debug_assert_matches};`.

## Bad

```rust
let result: Result<u32, &str> = Err("invalid digit");
assert!(matches!(result, Err(_)));
```

The assertion tells you that the pattern failed, but does not show the mismatching value as clearly as `assert_matches!` does.

## Good

```rust
use std::assert_matches;

let result: Result<&str, &str> = Ok("Alice");
assert_matches!(result, Ok("Alice"));

#[derive(Debug)]
struct StatusCode {
    value: u16,
}
let status = StatusCode { value: 200 };
assert_matches!(status, StatusCode { value: 200 });

let parsed: Result<u32, &str> = Err("invalid digit");
assert_matches!(parsed, Err(e) if e.contains("invalid"));
```

`assert_matches!` accepts patterns and an optional `if` guard, just like `matches!`. It does **not** have match-arm `=> { ... }` syntax. If you need to run arbitrary code with a bound value, use a normal `match`, `let ... else`, or another assertion after extracting the value.

## `debug_assert_matches!`

```rust
use std::debug_assert_matches;

let value = Some(42);
debug_assert_matches!(value, Some(x) if x > 0);
```

Like other debug assertions, `debug_assert_matches!` is disabled in optimized builds unless debug assertions are enabled, though its expression is still type-checked.

## Custom Error Enum

```rust
use std::assert_matches;

#[derive(Debug)]
enum ParseError {
    InvalidSyntax { line: usize, msg: String },
    UnexpectedEof,
}

fn parse(input: &str) -> Result<i32, ParseError> {
    if input == "bad" {
        Err(ParseError::InvalidSyntax {
            line: 1,
            msg: "bad input".into(),
        })
    } else {
        Ok(0)
    }
}

#[test]
fn test_parse_error() {
    assert_matches!(
        parse("bad"),
        Err(ParseError::InvalidSyntax { line: 1, .. })
    );
}
```

## Custom Failure Message

The macro also has an assertion-style custom-message form:

```rust
use std::assert_matches;

let value = Some(3);
assert_matches!(value, Some(x) if x > 0, "expected a positive value");
```

## See Also

- [test-doctest-examples](./test-doctest-examples.md) — Runnable doctest examples
- [test-descriptive-names](./test-descriptive-names.md) — Descriptive test naming
- [test-arrange-act-assert](./test-arrange-act-assert.md) — Test structure with AAA pattern
- [test-should-panic](./test-should-panic.md) — When to use `should_panic`
- [test-proptest-properties](./test-proptest-properties.md) — Property-based testing
