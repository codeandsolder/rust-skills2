# doc-hidden-setup

> Hide incidental doctest setup with `# ` while leaving the behavior users need to understand visible

## Why It Matters

Rustdoc treats a line beginning with `# ` inside a Rust doctest as hidden source: the line participates in compilation and execution but is omitted from the rendered code example. This is useful for imports, tiny helper definitions, fallible wrappers, and other setup that would distract from the API call being demonstrated.

Hidden setup is not a license to make examples mysterious. If constructing a value, selecting a feature, or configuring an option is important to successful use, show that code.

## Good: Hide Only Incidental Setup

```rust
/// Returns a normalized copy of a label.
///
/// # Examples
///
/// ```
/// # let raw = String::from("  Example  ");
/// let label = raw.trim().to_ascii_lowercase();
/// assert_eq!(label, "example");
/// ```
pub fn normalize_label(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn main() {
    assert_eq!(normalize_label("  Example  "), "example");
}
```

The fixture is hidden; the transformation and assertion remain visible.

## Hidden Fallible Wrapper

```rust
/// Parses a positive integer.
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
pub fn parse_count(value: &str) -> Result<u32, std::num::ParseIntError> {
    value.parse()
}

fn main() {
    assert_eq!(parse_count("42"), Ok(42));
}
```

This keeps error-propagation boilerplate out of the rendered example without changing what rustdoc compiles.

## Do Not Hide the API Contract

Suppose configuration is the point of the example. Then show it:

```rust
#[derive(Debug, PartialEq, Eq)]
struct Client {
    timeout_secs: u64,
}

impl Client {
    fn with_timeout(timeout_secs: u64) -> Self {
        Self { timeout_secs }
    }
}

fn main() {
    let client = Client::with_timeout(30);
    assert_eq!(client.timeout_secs, 30);
}
```

Hiding the constructor here would make the example shorter but less useful.

## Multi-Line Hidden Setup

Each physical source line that should disappear from rendered output needs its own hidden marker:

```rust
/// Returns the sum of a prepared fixture.
///
/// # Examples
///
/// ```
/// # let values = vec![
/// #     10,
/// #     20,
/// #     12,
/// # ];
/// let total: i32 = values.iter().sum();
/// assert_eq!(total, 42);
/// ```
pub fn fixture_example() {}

fn main() {}
```

Do not assume one leading `#` hides an entire syntactic construct.

## `no_run`, `compile_fail`, and `ignore` Solve Different Problems

Hidden lines affect presentation. Fence attributes affect how rustdoc tests the block:

- `no_run` compiles the doctest but does not execute it;
- `compile_fail` requires compilation to fail;
- `ignore` skips the doctest;
- ordinary Rust fences compile and run.

Use `no_run` for real code with undesirable runtime side effects, not `ignore`. Use `compile_fail` for an intentional compiler-rejected example. Prefer prose over marking incomplete pseudocode `ignore` just to avoid maintaining it.

```rust
/// Binds a local listener but does not run during doctests.
///
/// ```no_run
/// let listener = std::net::TcpListener::bind("127.0.0.1:0")?;
/// println!("{}", listener.local_addr()?);
/// # Ok::<(), std::io::Error>(())
/// ```
pub fn listener_example() {}

fn main() {}
```

## Edition 2024 Doctest Merging

Edition 2024 allows rustdoc to merge compatible doctests into fewer generated crates. This is a compilation optimization; each doctest still runs as its own test. Rustdoc automatically recognizes many cases that require a separate crate, including crate-level attributes and several macro-sensitive examples.

Do not add `standalone_crate` merely because hidden setup uses `$crate` or a helper macro; rustdoc can detect many such cases itself. Use `standalone_crate` when an example truly depends on separate generated-crate details that rustdoc cannot infer, such as assertions about source locations.

## Shared Setup in External Markdown

For substantial documentation reused across items, `#[doc = include_str!(...)]` can include a Markdown file. That example depends on a real repository file, so this corpus marks it explicitly instead of recording a missing-file compiler error:

<!-- rust-check: ignore; reason=requires repository Markdown file at the documented path -->
```rust
/// # Examples
#[doc = include_str!("../doc_tests/setup_and_example.md")]
pub fn shared_example() {}
```

For ordinary `include_str!`, the path is relative to the Rust source containing the macro invocation. In Edition 2024, if an included Markdown file contains a **doctest** that itself invokes `include!`, `include_str!`, or `include_bytes!`, that nested path is resolved relative to the Markdown file.

## Practical Guidance

- Hide imports, fixtures, and wrappers only when they are incidental.
- Keep configuration and construction visible when they teach the API contract.
- Remember that every hidden line still has to compile.
- Keep testing semantics (`no_run`, `compile_fail`, `ignore`) separate from presentation semantics (`# `).
- Classify external-file examples explicitly when the verifier's standalone harness cannot provide those files.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing useful examples
- [doc-question-mark](./doc-question-mark.md) - Using `?` in examples
- [test-doctest-examples](./test-doctest-examples.md) - Doctests as tests
- [doc-test-edition-2024](./doc-test-edition-2024.md) - Edition 2024 doctest behavior
- [doc-include-str](./doc-include-str.md) - External Markdown documentation
