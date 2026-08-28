# pat-matches-macro

> Use `matches!()` for boolean pattern tests

## Why It Matters

`matches!(value, Pattern)` is the idiomatic way to ask whether a value matches a pattern when the result itself is a boolean. It avoids a `match` whose only purpose is returning `true` or `false`, and it supports alternation and guards.

Use a normal `match` or `if let` when you need to extract a value for further work or perform different actions per branch.

## Bad: Boolean-Only `match`

<!-- rust-check: compile -->
```rust
enum Status {
    Active,
    Pending,
    Closed,
}

fn is_active(status: &Status) -> bool {
    match status {
        Status::Active => true,
        _ => false,
    }
}

fn main() {
    assert!(is_active(&Status::Active));
}
```

## Good

<!-- rust-check: compile -->
```rust
enum Status {
    Active,
    Pending,
    Closed,
}

fn is_active(status: &Status) -> bool {
    matches!(status, Status::Active)
}

fn is_small_digit(n: u32) -> bool {
    matches!(n, 1..=9)
}

fn is_positive(value: Option<i32>) -> bool {
    matches!(value, Some(n) if n > 0)
}

fn main() {
    assert!(is_active(&Status::Active));
    assert!(is_small_digit(7));
    assert!(is_positive(Some(3)));
    assert!(!is_positive(Some(-1)));
}
```

## Combining Variants

<!-- rust-check: compile -->
```rust
enum Status {
    Active,
    Pending,
    Closed,
}

fn is_terminal(status: &Status) -> bool {
    matches!(status, Status::Closed | Status::Pending)
}

fn main() {
    assert!(is_terminal(&Status::Closed));
    assert!(!is_terminal(&Status::Active));
}
```

## Good for `is_*` Helper Methods

`matches!` pairs well with predicate methods when the method is genuinely just a pattern test:

<!-- rust-check: compile -->
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Status {
    Active,
    Pending,
    Closed,
}

impl Status {
    pub fn is_active(&self) -> bool {
        matches!(self, Self::Active)
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Closed | Self::Pending)
    }
}

fn main() {
    assert!(Status::Active.is_active());
    assert!(Status::Pending.is_terminal());
}
```

## Asserting a Pattern in Tests

Rust 1.96 stabilized `assert_matches!` and `debug_assert_matches!`. They are exported from the `std` macro root but are not imported by the prelude, so import the macro itself:

<!-- rust-check: compile -->
```rust
use std::assert_matches;

fn parse(raw: &str) -> Result<u32, std::num::ParseIntError> {
    raw.parse()
}

fn main() {
    let result = parse("42");
    assert_matches!(result, Ok(n) if n == 42);
}
```

`assert_matches!` can produce a more pattern-oriented failure than `assert!(matches!(...))`. Use ordinary `assert_eq!` when exact equality is the clearer contract.

## Clippy

`clippy::match_like_matches_macro` catches many verbose boolean `match` expressions and is included in Clippy's style-oriented linting. Treat the suggestion as a readability improvement, not a requirement to replace matches that actually bind or branch on data.

## See Also

- [pat-exhaustive-enum](pat-exhaustive-enum.md) - exhaustive enum matching
- [name-is-has-bool](name-is-has-bool.md) - predicate naming
