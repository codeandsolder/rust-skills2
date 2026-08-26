# doc-examples-section

> Include `# Examples` with runnable code

## Why It Matters

Examples are the most valuable part of documentation. They show users exactly how to use your API. Rust's doc tests ensure examples stay correct as code evolves.

## Bad

```rust
/// Parses a string into a Foo.
pub fn parse(s: &str) -> Result<Foo, Error> {
    // No examples - users have to guess usage
}

/// A widget for doing things.
/// 
/// This widget is very useful.
pub struct Widget {
    // Still no examples
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
/// Parses a string into a Foo.
///
/// # Examples
///
/// ```
/// use my_crate::parse;
///
/// let foo = parse("hello").unwrap();
/// assert_eq!(foo.name(), "hello");
/// ```
///
/// Handles empty strings:
///
/// ```
/// use my_crate::parse;
///
/// let foo = parse("").unwrap();
/// assert!(foo.is_empty());
/// ```
pub fn parse(s: &str) -> Result<Foo, Error> {
    // ...
}
```

## Use ? Not unwrap()

```rust
/// Loads configuration from a file.
///
/// # Examples
///
/// ```
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// use my_crate::Config;
///
/// let config = Config::load("config.toml")?;
/// println!("Port: {}", config.port);
/// # Ok(())
/// # }
/// ```
pub fn load(path: &str) -> Result<Config, Error> {
    // ...
}
```

## Hide Setup Code

```rust
/// Processes items from a database.
///
/// # Examples
///
/// ```
/// # use my_crate::{Database, Item};
/// # fn get_db() -> Database { Database::mock() }
/// let db = get_db();
/// let items = db.process_items()?;
/// assert!(!items.is_empty());
/// # Ok::<(), my_crate::Error>(())
/// ```
pub fn process_items(&self) -> Result<Vec<Item>, Error> {
    // ...
}
```

## Multiple Examples

```rust
/// Creates a new buffer with the specified capacity.
///
/// # Examples
///
/// Basic usage:
///
/// ```
/// use my_crate::Buffer;
///
/// let buf = Buffer::with_capacity(1024);
/// assert_eq!(buf.capacity(), 1024);
/// ```
///
/// Zero capacity creates an empty buffer:
///
/// ```
/// use my_crate::Buffer;
///
/// let buf = Buffer::with_capacity(0);
/// assert!(buf.is_empty());
/// ```
pub fn with_capacity(cap: usize) -> Self {
    // ...
}
```

## Show Error Cases

```rust
/// Divides two numbers.
///
/// # Examples
///
/// ```
/// use my_crate::divide;
///
/// assert_eq!(divide(10, 2), Ok(5));
/// ```
///
/// Division by zero returns an error:
///
/// ```
/// use my_crate::{divide, MathError};
///
/// assert_eq!(divide(10, 0), Err(MathError::DivisionByZero));
/// ```
pub fn divide(a: i32, b: i32) -> Result<i32, MathError> {
    // ...
}
```

## Edition 2024: standalone_crate Tag

Rust Edition 2024 compiles all doc tests in a single binary for performance.
If a doc test needs its own crate (e.g., for `no_std` or `extern crate`),
use the `standalone_crate` language tag:

```rust
/// ```standalone_crate
/// #![no_std]
/// #![no_main]
/// // This must compile as its own crate
/// ```
```

## Edition 2024: Nested Include Paths

In Edition 2024, `#[doc = include_str!("...")]` paths within doc comments
resolve **relative to the Markdown file** (if the doc comment was itself
produced by an `include_str!`), not the Rust source file. See
[doc-include-str](./doc-include-str.md) for details.

## Shared Examples with include_str

Use `#[doc = include_str!("...")]` to share the same example across
multiple items:

```rust
/// # Examples
///
#[doc = include_str!("../examples/basic_usage.md")]
pub fn function_a() { }

/// # Examples
///
#[doc = include_str!("../examples/basic_usage.md")]
pub fn function_b() { }
```

## Lints

```rust
#![warn(clippy::needless_doctest_main)]
```

The `needless_doctest_main` clippy lint catches doc tests that wrap
code in an explicit `fn main() {}` when it's unnecessary.

On nightly, enable `missing_doc_code_examples` to require examples on
all public items:

```rust
#![warn(missing_doc_code_examples)]
```

## Running Doc Tests

```bash
# Run all doc tests
cargo test --doc

# Run doc tests for specific item
cargo test --doc my_function
```

## See Also

- [doc-question-mark](doc-question-mark.md) - Use ? in examples
- [doc-hidden-setup](doc-hidden-setup.md) - Hide setup code with #
- [doc-errors-section](doc-errors-section.md) - Document error conditions
- [doc-include-str](doc-include-str.md) - Shared examples via include_str
- [doc-test-edition-2024](doc-test-edition-2024.md) - Edition 2024 doctest migration
