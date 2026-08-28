# test-doctest-examples

> Keep public documentation examples executable as doctests when practical

## Why It Matters

Rustdoc can compile and run Rust code fences embedded in documentation. That turns examples into compatibility tests: when an API changes, stale examples fail instead of silently teaching code that no longer works.

Not every documentation block should run. Rustdoc provides `no_run`, `compile_fail`, platform-specific ignore attributes, and `ignore` for cases where execution or compilation is intentionally unsuitable. Prefer the narrowest truthful fence behavior.

## Bad: Example-Shaped Prose Is Not Tested

```rust
/// Parses a number from a string.
///
/// Example (plain prose, not a rustdoc code fence):
/// `let n = parse_number("42");`
pub fn parse_number(s: &str) -> i32 {
    s.parse().unwrap()
}

fn main() {
    assert_eq!(parse_number("42"), 42);
}
```

Readers see code, but rustdoc does not treat that inline prose as an executable example.

## Good: Use a Rust Code Fence

```rust
/// Parses a number from a string.
///
/// # Examples
///
/// ```
/// let n: i32 = "42".parse().unwrap();
/// assert_eq!(n, 42);
/// ```
pub fn parse_number(s: &str) -> i32 {
    s.parse().unwrap()
}

fn main() {}
```

For a real library API, doctests normally import the documented crate by its actual crate name and call its public items as downstream users would.

## Hiding Setup Code

Lines beginning with `#` inside a doctest are compiled but hidden from rendered documentation. This is useful for imports, fixtures, and return-type scaffolding.

<!-- rust-check: compile -->
```rust
use std::path::Path;

/// Reads a file into a string.
///
/// # Examples
///
/// ```
/// # use std::io::Write;
/// # let mut file = tempfile::NamedTempFile::new().unwrap();
/// # writeln!(file, "test data").unwrap();
/// # let path = file.path();
/// use sample_api::process_file;
///
/// let result = process_file(path)?;
/// assert!(result.contains("test data"));
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub fn process_file(path: &Path) -> std::io::Result<String> {
    std::fs::read_to_string(path)
}

fn main() {}
```

`sample_api` represents the actual crate name in this teaching example. In production documentation, use the package's real library crate path.

## Showing Error Handling

A doctest can return a `Result` so examples can use `?` without cluttering the visible code.

<!-- rust-check: compile -->
```rust
#[derive(Debug, PartialEq, Eq)]
pub struct Email(String);

#[derive(Debug, PartialEq, Eq)]
pub struct EmailError;

impl Email {
    pub fn parse(raw: &str) -> Result<Self, EmailError> {
        raw.contains('@')
            .then(|| Self(raw.to_owned()))
            .ok_or(EmailError)
    }

    pub fn domain(&self) -> &str {
        self.0.split_once('@').map_or("", |(_, domain)| domain)
    }
}

/// Parse an email address.
///
/// # Examples
///
/// ```
/// use sample_api::Email;
///
/// let email = Email::parse("user@example.com")?;
/// assert_eq!(email.domain(), "example.com");
/// # Ok::<(), sample_api::EmailError>(())
/// ```
///
/// # Errors
///
/// ```
/// use sample_api::Email;
/// assert!(Email::parse("not-an-email").is_err());
/// ```
pub fn documented_email_example() {}

fn main() {}
```

## `no_run` and `ignore`

Use `no_run` when the example should compile but executing it is undesirable, such as a server loop or destructive operation. Use `ignore` only when even compiling the example in the normal doctest environment is intentionally inappropriate.

<!-- rust-check: compile -->
```rust
pub struct Server;

impl Server {
    pub fn new() -> Self {
        Self
    }

    pub fn run(&self) -> ! {
        loop {
            std::thread::park();
        }
    }
}

/// ```no_run
/// use sample_api::Server;
///
/// // Compiles, but rustdoc will not execute the blocking server loop.
/// Server::new().run();
/// ```
pub fn server_example() {}

/// Platform/toolchain-specific example that this crate chooses not to compile
/// in ordinary doctest runs.
///
/// ```ignore
/// use platform_sdk::Feature;
/// let _ = Feature::new();
/// ```
pub fn platform_example() {}

fn main() {}
```

Where possible, prefer target-specific rustdoc ignore attributes such as `ignore-windows` or `ignore-x86_64` over an unconditional `ignore` when the limitation is truly target-specific.

## `compile_fail`

Negative API examples can be tested too:

<!-- rust-check: compile -->
```rust
pub struct UniqueHandle(u64);

impl UniqueHandle {
    pub fn new() -> Self {
        Self(1)
    }
}

/// `UniqueHandle` intentionally does not implement `Clone`.
///
/// ```compile_fail
/// use sample_api::UniqueHandle;
///
/// let handle = UniqueHandle::new();
/// let duplicate = handle.clone();
/// ```
pub fn unique_handle_example() {}

fn main() {}
```

A `compile_fail` doctest verifies that the snippet fails somewhere; it is not a precise diagnostic assertion framework. For compiler-error APIs where the exact error matters, use a dedicated UI/trybuild-style test.

## Running Doctests

```bash
cargo test
cargo test --doc
cargo test --doc some_name_filter
cargo test --doc -- --test-threads=1
```

Edition 2024 rustdoc may compile compatible doctests together for performance, while still running individual doctests in separate processes. Do not rely on generated source layout or incidental ordering.

## Snapshot Assertions in Doctests

Insta snapshot assertions **can** be used in doctests; current Insta itself contains doctest snapshot coverage. They are not forbidden by rustdoc isolation.

The practical question is whether snapshots improve that particular documentation example. File snapshots are tied to source/test identity and can be more awkward to review for generated doctest contexts. Inline snapshots or ordinary assertions are often simpler for small documentation examples.

```rust
/// A simple doctest usually needs no snapshot framework.
///
/// ```
/// let rendered = format!("value={}", 42);
/// assert_eq!(rendered, "value=42");
/// ```
pub fn simple_documentation_assertion() {}

fn main() {}
```

Use Insta in doctests when snapshot review genuinely adds value, not because doctests require a different assertion mechanism.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Documentation structure
- [doc-hidden-setup](./doc-hidden-setup.md) - Hidden `#` setup lines
- [doc-question-mark](./doc-question-mark.md) - `?` in examples
- [test-snapshot-testing](./test-snapshot-testing.md) - Snapshot testing workflows

## References

- [rustdoc book: documentation tests](https://doc.rust-lang.org/rustdoc/write-documentation/documentation-tests.html)
- [Insta documentation](https://insta.rs/docs/)
