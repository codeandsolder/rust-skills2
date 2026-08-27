# test-should-panic

> Use `#[should_panic]` for tests whose success condition is a deliberate panic

## Why It Matters

A normal Rust test passes when it returns successfully. `#[should_panic]` inverts that condition: the test passes only if it panics.

Use it for APIs whose contract intentionally includes a panic, such as invariant violations or operations documented to reject invalid programmer input. Do not use panic tests for recoverable errors that should be represented with `Result` or `Option`.

## Good: Test an Intentional Panic

```rust
fn divide_exact(numerator: i32, denominator: i32) -> i32 {
    assert!(denominator != 0, "denominator must be nonzero");
    numerator / denominator
}

#[test]
#[should_panic]
fn zero_denominator_panics() {
    let _ = divide_exact(10, 0);
}
```

If the panic message is part of the behavior you want to pin down, use `expected`:

```rust
fn divide_exact(numerator: i32, denominator: i32) -> i32 {
    assert!(denominator != 0, "denominator must be nonzero");
    numerator / denominator
}

#[test]
#[should_panic(expected = "denominator must be nonzero")]
fn zero_denominator_has_clear_message() {
    let _ = divide_exact(10, 0);
}
```

The `expected` string is a **substring match** against the panic message. Prefer matching a message your own code controls rather than text produced by an implementation detail of the standard library or a dependency.

## Good: Test an Invariant at Construction

```rust
#[derive(Debug)]
struct NonEmpty<T>(Vec<T>);

impl<T> NonEmpty<T> {
    fn new(items: Vec<T>) -> Self {
        assert!(!items.is_empty(), "NonEmpty requires at least one item");
        Self(items)
    }
}

#[test]
#[should_panic(expected = "NonEmpty requires at least one item")]
fn rejects_empty_input() {
    let _ = NonEmpty::<i32>::new(Vec::new());
}

#[test]
fn accepts_non_empty_input() {
    let values = NonEmpty::new(vec![1, 2, 3]);
    assert_eq!(values.0.len(), 3);
}
```

## Do Not Use `should_panic` for Recoverable Errors

```rust
#[derive(Debug, PartialEq)]
enum ParseError {
    Empty,
}

fn parse_count(input: &str) -> Result<u32, ParseError> {
    if input.is_empty() {
        return Err(ParseError::Empty);
    }
    input.parse().map_err(|_| ParseError::Empty)
}

#[test]
fn empty_input_is_an_error() {
    assert_eq!(parse_count(""), Err(ParseError::Empty));
}
```

A panic test would hide the more useful contract here: callers can inspect and handle the error.

## `assert_matches!` Is for Values, Not Panics (Rust 1.96+)

`assert_matches!` is useful when a function returns an enum and you care about its variant or fields. It is not a replacement for `#[should_panic]`; it tests a returned value rather than an unwinding control-flow event.

```rust
use std::assert_matches;

#[derive(Debug)]
enum ConfigError {
    ParseFailed { line: usize },
    MissingField { name: String },
}

fn parse_config(input: &str) -> Result<(), ConfigError> {
    if input == "bad" {
        Err(ConfigError::ParseFailed { line: 1 })
    } else {
        Ok(())
    }
}

#[test]
fn reports_parse_line() {
    assert_matches!(
        parse_config("bad"),
        Err(ConfigError::ParseFailed { line: 1 })
    );
}
```

`assert_matches!` prints the debug representation of a non-matching value, which is often more informative than `assert!(matches!(...))`.

## `should_panic` Tests Must Return `()`

Although ordinary `#[test]` functions may return types implementing `Termination`, including `Result<(), E>`, a test annotated with `#[should_panic]` must return `()`.

If setup is fallible, perform it before the operation whose panic is under test and make setup failures explicit:

```rust
fn setup_value() -> Result<i32, &'static str> {
    Ok(42)
}

fn reject_answer(value: i32) {
    assert!(value != 42, "answer is forbidden");
}

#[test]
#[should_panic(expected = "answer is forbidden")]
fn rejects_answer() {
    let value = setup_value().expect("test fixture should initialize");
    reject_answer(value);
}
```

Do not write a `#[should_panic]` test returning `Result`: that is not a valid test signature.

## When `catch_unwind` Is Appropriate

`std::panic::catch_unwind` is more cumbersome than `#[should_panic]`, but it is the right tool when the test must continue after the panic, inspect the panic payload, or verify additional post-unwind state.

```rust
use std::panic::{catch_unwind, AssertUnwindSafe};

#[test]
fn panic_does_not_prevent_followup_assertion() {
    let mut touched = false;

    let result = catch_unwind(AssertUnwindSafe(|| {
        touched = true;
        panic!("boom");
    }));

    assert!(result.is_err());
    assert!(touched);
}
```

`catch_unwind` only catches unwinding panics. Code running with an aborting panic strategy does not provide an unwind to catch.

## Practical Guidance

- Use plain `#[should_panic]` when any panic is sufficient.
- Add `expected = "..."` when distinguishing the intended panic from an accidental one matters.
- Match messages your code owns; dependency/compiler panic wording can change.
- Prefer `Result`/`Option` assertions for recoverable failures.
- Prefer `assert_matches!` for returned enum shapes.
- Use `catch_unwind` only when the test needs control after the panic.

## See Also

- [test-assert-matches](./test-assert-matches.md) — pattern-based value assertions
- [err-result-over-panic](./err-result-over-panic.md) — choosing `Result` versus panic
- [err-expect-bugs-only](./err-expect-bugs-only.md) — appropriate `expect` usage
- [test-descriptive-names](./test-descriptive-names.md) — test naming
