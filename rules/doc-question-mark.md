# doc-question-mark

> Use `?` in examples, not `.unwrap()`

## Why It Matters

Doc examples should model best practices. Using `.unwrap()` teaches users to ignore errors, while `?` demonstrates proper error propagation. Examples with `?` also fail the doctest if an error occurs, catching bugs in documentation.

Rust doctests wrap examples in a function that returns `Result<(), E>` by default when you use `?`, making this pattern easy to adopt.

## Bad

```rust
/// Reads a configuration file.
///
/// # Examples
///
/// ```
/// let config = Config::from_file("config.toml").unwrap();
/// println!("{:?}", config.database_url);
/// ```
pub fn from_file(path: &str) -> Result<Config, Error> {
    // ...
}

/// Fetches data from the API.
///
/// # Examples
///
/// ```
/// let client = Client::new();
/// let response = client.get("https://api.example.com").unwrap();
/// let data: Data = response.json().unwrap();
/// ```
pub async fn get(&self, url: &str) -> Result<Response, Error> {
    // ...
}
```

## Good

```rust
/// Reads a configuration file.
///
/// # Examples
///
/// ```
/// # use my_crate::{Config, Error};
/// # fn main() -> Result<(), Error> {
/// let config = Config::from_file("config.toml")?;
/// println!("{:?}", config.database_url);
/// # Ok(())
/// # }
/// ```
pub fn from_file(path: &str) -> Result<Config, Error> {
    // ...
}

/// Fetches data from the API.
///
/// # Examples
///
/// ```no_run
/// # use my_crate::{Client, Data, Error};
/// # async fn example() -> Result<(), Error> {
/// let client = Client::new();
/// let response = client.get("https://api.example.com").await?;
/// let data: Data = response.json().await?;
/// # Ok(())
/// # }
/// ```
pub async fn get(&self, url: &str) -> Result<Response, Error> {
    // ...
}
```

## Doctest Wrapper Pattern

Rust wraps doc examples in a function. You can make this explicit:

```rust
/// # Examples
///
/// ```
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let value = parse_config("key=value")?;
/// assert_eq!(value.key, "value");
/// # Ok(())
/// # }
/// ```
```

Or use the implicit wrapper (Rust 2021+):

```rust
/// # Examples
///
/// ```
/// # use my_crate::parse_config;
/// let value = parse_config("key=value")?;
/// assert_eq!(value.key, "value");
/// # Ok::<(), my_crate::Error>(())
/// ```
```

The `Ok::<(), Error>(())` tail pattern is useful when you want to avoid
wrapping in `fn main() -> Result`.

### Async Doc Tests with ?

For async functions, wrap in an async block:

```rust
/// ```
/// # async fn wrapper() -> Result<(), my_crate::Error> {
/// let result = my_crate::fetch_data().await?;
/// println!("{result}");
/// # Ok(())
/// # }
/// ```
```

## When to Use `.unwrap()`

There are specific cases where `.unwrap()` is acceptable in examples:

```rust
/// # Examples
///
/// ```
/// // Static regex that is known at compile time to be valid
/// let re = Regex::new(r"^\d{4}-\d{2}-\d{2}$").unwrap();
///
/// // Parsing a literal that cannot fail
/// let n: i32 = "42".parse().unwrap();
/// ```
```

But still prefer `?` when demonstrating error handling patterns.

## Comparison

| Pattern | Behavior on Error | Teaches |
|---------|-------------------|---------|
| `.unwrap()` | Panics with generic message | Bad habits |
| `.expect()` | Panics with custom message | Slightly better |
| `?` | Propagates error, test fails | Best practices |

## Lints

Enable `clippy::needless_doctest_main` to catch doc tests with unnecessary
explicit `fn main()` wrappers:

```rust
#![warn(clippy::needless_doctest_main)]
```

This helps keep examples clean by removing boilerplate that rustdoc
generates automatically.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hiding setup code
- [err-question-mark](./err-question-mark.md) - Error propagation
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest migration
