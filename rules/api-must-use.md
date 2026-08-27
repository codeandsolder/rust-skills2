# api-must-use

> Add `#[must_use]` when silently discarding a value is plausibly a bug; rely on the built-in `unused_must_use` semantics instead of treating every return value alike

## Why It Matters

`#[must_use]` asks the compiler to warn when a value is produced as an expression statement and then discarded. It is useful for values whose purpose is normally in the returned value itself: results of pure computations, lazy values, builders, guards, and domain objects that have no useful effect when immediately dropped.

Do not add it mechanically to every function. A warning that fires for normal intentional usage teaches callers to ignore warnings instead of catching bugs.

## Good: Mark a Returned Value Whose Effect Is in the Value

```rust
#[must_use = "the checksum is the result of this computation"]
fn checksum(bytes: &[u8]) -> u32 {
    bytes.iter().map(|&b| u32::from(b)).sum()
}

fn main() {
    let value = checksum(&[1, 2, 3]);
    assert_eq!(value, 6);
}
```

A discarded call such as `checksum(&data);` now triggers `unused_must_use`.

## Types Can Carry the Contract

```rust
#[must_use = "dropping this request without sending it has no effect"]
struct RequestBuilder {
    path: String,
}

impl RequestBuilder {
    fn new(path: impl Into<String>) -> Self {
        Self { path: path.into() }
    }

    #[must_use]
    fn with_prefix(mut self, prefix: &str) -> Self {
        self.path = format!("{prefix}{}", self.path);
        self
    }

    fn send(self) -> String {
        self.path
    }
}

fn main() {
    let sent = RequestBuilder::new("/users")
        .with_prefix("https://example.test")
        .send();
    assert_eq!(sent, "https://example.test/users");
}
```

Putting `#[must_use]` on the type covers expressions that produce that type. A method-level annotation can still be useful when the method's return value deserves a more specific message.

## `Result`, Iterators, Futures, and Other Existing Must-Use Types

Many standard types already carry `#[must_use]`. Do not add redundant attributes merely because a function returns `Result` or an iterator.

```rust
fn parse_port(raw: &str) -> Result<u16, std::num::ParseIntError> {
    raw.parse()
}

fn main() {
    assert_eq!(parse_port("443").unwrap(), 443);

    let values = [1, 2, 3];
    let doubled: Vec<_> = values.iter().map(|x| x * 2).collect();
    assert_eq!(doubled, [2, 4, 6]);
}
```

Ignoring `parse_port("443")` already warns because `Result` is must-use. Likewise, iterator adapters inherit the iterator type's must-use behavior.

## When the Return Value Is Optional Information

A side-effecting operation can legitimately return metadata that callers often do not care about. In that case, forcing every caller to write `let _ = ...` may add noise rather than safety.

```rust
fn record_metric(name: &str, value: u64) -> u64 {
    println!("{name}={value}");
    value
}

fn main() {
    record_metric("requests", 3);
}
```

Whether that return value deserves `#[must_use]` is an API-design decision, not a rule derived from its type alone.

## Rust 1.92+: Uninhabited Error/Break Types Do Not Trigger `unused_must_use`

The language has a narrow exception for must-use container types that cannot represent the must-handle branch. `Result<(), E>` does not trigger `unused_must_use` when `E` is uninhabited; likewise for `ControlFlow<B, ()>` when `B` is uninhabited.

Use a stable uninhabited type in examples. `core::convert::Infallible` works on stable Rust; using `!` as a generic type argument is still not the right stable example.

```rust
#![deny(unused_must_use)]

use core::convert::Infallible;
use core::ops::ControlFlow;

fn infallible_result() -> Result<(), Infallible> {
    Ok(())
}

fn cannot_break() -> ControlFlow<Infallible, ()> {
    ControlFlow::Continue(())
}

fn main() {
    // Rust 1.92+: accepted despite Result/ControlFlow being must-use because
    // their error/break variants cannot be constructed.
    infallible_result();
    cannot_break();
}
```

This does **not** make ordinary `Result<(), E>` optional to handle. If `E` has any inhabitant, the usual must-use warning applies.

## Messages Should Explain the Consequence

```rust
#[must_use = "this returns a normalized copy; it does not mutate the input"]
fn normalized(input: &str) -> String {
    input.trim().to_lowercase()
}

fn main() {
    assert_eq!(normalized("  Hello "), "hello");
}
```

Prefer a message that tells the caller why discarding the value is suspicious. Repeating “must use this value” adds little beyond the lint itself.

## Lint Policy

Projects that want ignored must-use values to be hard errors can elevate the built-in lint:

```rust
#![deny(unused_must_use)]

fn main() {
    let _ = "42".parse::<u32>(); // explicit discard is still permitted
}
```

An explicit `let _ = ...` communicates that discarding was intentional. Reserve stronger local handling (`?`, `match`, logging, propagation) for cases where the value actually matters.

Clippy's `must_use_candidate`, `return_self_not_must_use`, and `double_must_use` can help review API consistency, but enabling them is a project choice rather than a universal requirement.

## See Also

- [api-builder-must-use](./api-builder-must-use.md) — builder-specific guidance
- [err-result-over-panic](./err-result-over-panic.md) — handling recoverable errors
- [lint-deny-correctness](./lint-deny-correctness.md) — lint policy

## References

- [Rust Reference: `must_use`](https://doc.rust-lang.org/reference/attributes/diagnostics.html#the-must_use-attribute)
- [`unused_must_use` lint](https://doc.rust-lang.org/rustc/lints/listing/warn-by-default.html#unused-must-use)
