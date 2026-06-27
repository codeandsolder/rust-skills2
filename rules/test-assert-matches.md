# test-assert-matches

> Use `assert_matches!` / `debug_assert_matches!` (Rust 1.96+) for pattern-based assertions

## Why It Matters

Pattern matching on test results is common — checking enum variants, error kinds, or partial data. `assert!(matches!(..))` gives poor diagnostics on failure: it only says "assertion failed". `assert_matches!` provides the actual value in the failure message, making debugging much faster. Stabilized in Rust 1.96.0.

Must be imported explicitly with `use std::assert_matches;`.

## Bad

```rust
// Poor diagnostics — only says "assertion failed"
assert!(matches!(result, Ok(_)));

// No context on which variant was returned
assert!(matches!(response.status, StatusCode { value: 200 }));

// No information about the actual value
assert!(matches!(parse("bad input"), Err(_)));
```

## Good

```rust
use std::assert_matches;

assert_matches!(result, Ok(user));
// Failure: "assertion failed: expected Ok(_), got Err(InvalidInput("missing field"))"

assert_matches!(response.status, StatusCode { value: 200 });
// Failure: "expected StatusCode { value: 200 }, got StatusCode { value: 403 }"

// With debug output for complex values
assert_matches!(parse("bad input"), Err(e) => {
    assert!(e.to_string().contains("invalid"));
});
```

## debug_assert_matches!

```rust
use std::assert_matches;

// Only checked in debug builds — zero cost in release
debug_assert_matches!(internal_invariant(), Ok(_));

// Useful for hot paths where the check is redundant after validation
```

## With Custom Error Enums

```rust
use std::assert_matches;

#[derive(Debug)]
enum ParseError {
    InvalidSyntax { line: usize, msg: String },
    UnexpectedEof,
}

fn parse(input: &str) -> Result<i32, ParseError> { /* ... */ }

#[test]
fn test_parse_error() {
    let result = parse("bad");

    // Before (weak diagnostics)
    // assert!(matches!(result, Err(ParseError::InvalidSyntax { .. })));

    // After (full diagnostic on failure)
    assert_matches!(result, Err(ParseError::InvalidSyntax { line: 1, .. }));
}
```

## With proptest

```rust
use std::assert_matches;
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_parse_always_returns_ok_or_syntax_error(input in ".*") {
        let result = parse(&input);
        // Clear diagnostic on failures during shrinking
        assert_matches!(result, Ok(_) | Err(ParseError::InvalidSyntax { .. }));
    }
}
```

## Debug Assertions in Tests

```rust
use std::assert_matches;

#[test]
fn test_debug_only_invariant() {
    let data = setup_large_dataset();
    // Only checked in debug/test builds
    debug_assert_matches!(validate_integrity(&data), Ok(()));
    let result = process(&data);
    assert!(result.is_ok());
}
```

## See Also

- [test-doctest-examples](./test-doctest-examples.md) — Runnable doctest examples
- [test-descriptive-names](./test-descriptive-names.md) — Descriptive test naming
- [test-arrange-act-assert](./test-arrange-act-assert.md) — Test structure with AAA pattern

## References

- [Rust 1.96.0 Release Notes](https://releases.rs/docs/1.96.0/) — assert_matches! stabilization
- [Stabilization PR #137487](https://github.com/rust-lang/rust/pull/137487)
- [test-should-panic](./test-should-panic.md) — When to use should_panic vs assert_matches
- [test-proptest-properties](./test-proptest-properties.md) — Property-based testing with assert_matches
