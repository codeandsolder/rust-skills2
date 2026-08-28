# doc-examples-section

> Add focused `# Examples` sections when an example materially clarifies how to use the API

## Why It Matters

Rustdoc examples can serve two jobs at once: they teach callers how an API is meant to be used, and runnable doctests keep that usage synchronized with the code. A useful example should emphasize the contract or workflow a reader actually needs rather than reproducing a large amount of setup.

Not every public item needs its own example. Small accessors and self-evident trait implementations can often rely on surrounding type/module documentation. Put examples where they explain construction, error handling, state transitions, feature-dependent behavior, or other non-obvious usage.

## Good: A Small Runnable Example

```rust
/// Returns the number of Unicode scalar values in `text`.
///
/// # Examples
///
/// ```
/// assert_eq!(char_count("café"), 4);
/// ```
pub fn char_count(text: &str) -> usize {
    text.chars().count()
}

fn main() {
    assert_eq!(char_count("café"), 4);
}
```

The documentation demonstrates observable behavior and the surrounding rule example is also valid standalone Rust.

## Use `?` When Fallible Composition Is the Point

Hidden doctest lines can provide a fallible wrapper without distracting from the API call:

```rust
/// Parses a decimal integer.
///
/// # Examples
///
/// ```
/// # fn main() -> Result<(), std::num::ParseIntError> {
/// let value: u32 = "42".parse()?;
/// assert_eq!(value, 42);
/// # Ok(())
/// # }
/// ```
pub fn parse_decimal(text: &str) -> Result<u32, std::num::ParseIntError> {
    text.parse()
}

fn main() {
    assert_eq!(parse_decimal("42"), Ok(42));
}
```

Use `unwrap()` when panicking is genuinely part of a tiny assertion/example and makes the example clearer; do not mechanically replace every `unwrap()` with a hidden `Result` wrapper.

## Hide Incidental Setup, Not the Concept Being Taught

```rust
/// Returns the first configured endpoint.
///
/// # Examples
///
/// ```
/// # let endpoints = vec![String::from("https://example.test")];
/// let first = endpoints.first().map(String::as_str);
/// assert_eq!(first, Some("https://example.test"));
/// ```
pub fn first_endpoint(endpoints: &[String]) -> Option<&str> {
    endpoints.first().map(String::as_str)
}

fn main() {
    let endpoints = vec![String::from("https://example.test")];
    assert_eq!(first_endpoint(&endpoints), Some("https://example.test"));
}
```

If configuration or construction is the thing users need to learn, show it instead of hiding it.

## Choose Doctest Attributes Deliberately

Rustdoc code-block attributes have different semantics:

- ordinary Rust fences are compiled and run as doctests;
- `no_run` compiles the example but does not execute it;
- `compile_fail` requires the example to fail compilation;
- `ignore` skips the doctest and should be reserved for cases that genuinely cannot be tested in the normal environment;
- edition tags such as `edition2024` select the edition for that block;
- `standalone_crate` requests a separate doctest crate instead of Edition 2024 doctest merging.

Do not mark broken or pseudocode examples `ignore` merely to silence CI. Prefer a real runnable example, `compile_fail` for an intentional compiler error, or prose for schematic pseudocode.

## `no_run` Still Checks the Example

```rust
/// Starts a long-running service.
///
/// # Examples
///
/// ```no_run
/// let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
/// println!("listening on {}", listener.local_addr()?);
/// # Ok::<(), std::io::Error>(())
/// ```
pub fn service_documented() {}

fn main() {}
```

Use `no_run` for examples that should type-check but should not perform their real side effects during doctests.

## Edition 2024 Doctest Merging

Edition 2024 lets rustdoc merge compatible doctests into fewer generated crates to reduce compile time. Individual doctests still behave as separate tests. Rustdoc automatically keeps many incompatible cases separate, including examples with crate-level attributes, `compile_fail`, edition overrides, and several macro-sensitive cases.

Use `standalone_crate` only when the example truly depends on separate-crate compilation and rustdoc cannot infer that requirement itself—for example, code whose expected `Location::caller()` line numbers depend on its generated crate layout.

```rust
/// Demonstrates the `standalone_crate` fence attribute.
///
/// ```standalone_crate
/// let caller = std::panic::Location::caller();
/// assert!(caller.line() > 0);
/// ```
pub fn location_example() {}

fn main() {}
```

## Shared Documentation with `include_str!`

External Markdown can be included into an item's documentation when sharing a substantial example is worthwhile:

<!-- rust-check: compile -->
```rust
/// # Examples
#[doc = include_str!("../examples/basic_usage.md")]
pub fn function_a() {}
```

The verifier provides a small UTF-8 Markdown fixture at this exact repository-relative path, so the example checks the `include_str!` path and attribute syntax rather than being skipped. That fixture does not prove that arbitrary real-world Markdown is good documentation; documentation rendering and doctests still belong in a real crate's `cargo doc` / `cargo test --doc` checks.

For ordinary `include_str!`, the path is resolved relative to the Rust source file containing the macro invocation. Edition 2024 adds a more specific doctest rule: if an included Markdown document contains a doctest that itself calls `include!`, `include_str!`, or `include_bytes!`, those nested paths are resolved relative to the Markdown file. It does not mean arbitrary `#[doc = include_str!(...)]` text inside Markdown becomes a Rust attribute.

## Useful Lints and Commands

`clippy::needless_doctest_main` can flag explicit `fn main()` wrappers that rustdoc does not need. Run doctests with:

```bash
cargo test --doc
```

Build documentation with warnings promoted when you want broken links and other rustdoc warnings to gate CI:

```bash
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps
```

## Practical Guidance

- Add examples where they explain behavior a reader could plausibly get wrong.
- Keep the visible code focused; hide only incidental setup.
- Prefer doctests that actually compile and run.
- Use `no_run`, `compile_fail`, `ignore`, and `standalone_crate` for their documented semantics rather than as generic escape hatches.
- In a compile-check harness, provide deterministic external-file fixtures when the path dependency itself is what the example needs to verify.

## See Also

- [doc-question-mark](./doc-question-mark.md) - Using `?` in examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hidden doctest setup
- [doc-errors-section](./doc-errors-section.md) - Documenting error conditions
- [doc-include-str](./doc-include-str.md) - External documentation with `include_str!`
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest behavior
