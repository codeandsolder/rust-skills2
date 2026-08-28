# doc-test-edition-2024

> Account for Edition 2024 rustdoc doctest merging, `standalone_crate`, and source-relative nested includes

## Why It Matters

Starting in Edition 2024, rustdoc **attempts to merge compatible doctests** into one compiled test crate. This reduces compilation overhead. The individual doctests are still run in separate processes, so merging does not make their runtime globals shared.

Rustdoc automatically keeps some incompatible examples separate, including `compile_fail` tests, examples with edition tags or crate-wide attributes, and macro definitions that use `$crate`. A smaller set of examples depend on compilation layout in ways rustdoc cannot infer; those may need the `standalone_crate` fence attribute.

Edition 2024 also changes nested `include!`, `include_str!`, and `include_bytes!` path resolution for doctests originating in included Markdown: paths are now relative to the Markdown file containing the doctest.

## Combined Doctests

A normal pair of doctests can be compiled into the same generated test crate:

```rust
/// Adds two numbers.
///
/// ```
/// assert_eq!(1 + 1, 2);
/// ```
pub fn add_one_plus_one() -> i32 {
    2
}

/// Multiplies two numbers.
///
/// ```
/// assert_eq!(2 * 3, 6);
/// ```
pub fn multiply_two_by_three() -> i32 {
    6
}

fn main() {}
```

Do not write tests that depend on the exact generated module path, line number, or other details of rustdoc's combined source layout.

## `standalone_crate` for Layout-Sensitive Tests

Use `standalone_crate` when the doctest is sensitive to generated-crate layout and rustdoc cannot automatically detect that requirement. `Location::caller()` assertions are the canonical example:

```rust
/// A layout-sensitive documentation test.
///
/// ```standalone_crate
/// let location = std::panic::Location::caller();
/// assert!(location.line() > 0);
/// ```
pub fn layout_sensitive_example() {}

fn main() {}
```

Do **not** add `standalone_crate` mechanically to every `no_std`, `compile_fail`, edition-specific, or crate-attribute example. Rustdoc already detects several classes that cannot be merged. Run `cargo test --doc` after an edition migration and add `standalone_crate` only when the example actually needs independent compilation and rustdoc does not infer it.

## `$crate` in Macro Definitions

`$crate` is a declarative-macro metavariable used inside macro definitions; it is not a path you can write directly in ordinary Rust expressions. For example:

```rust
pub const VERSION: &str = "1.0.0";

#[macro_export]
macro_rules! crate_version {
    () => {
        $crate::VERSION
    };
}

fn main() {
    assert_eq!(crate_version!(), "1.0.0");
}
```

For Edition 2024 doctest merging, rustdoc recognizes macro definitions that use `$crate` as incompatible with merging and keeps those doctests separate. That is different from claiming that `$crate` suddenly became available as an ordinary expression inside doctests.

## Nested Include Paths

Suppose the project layout is:

```text
project/
├── README.md
├── examples/
│   └── data.bin
└── src/
    └── lib.rs
```

and `src/lib.rs` contains:

```text
#![doc = include_str!("../README.md")]
```

If `README.md` contains this doctest (shown with `~` fences here so this rule's single-file verifier does not treat the illustrative external-file snippet as one of its own Rust examples):

```text
~~~rust
let bytes = include_bytes!("examples/data.bin");
assert!(!bytes.is_empty());
~~~
```

then in Edition 2024 the nested `include_bytes!` path is resolved relative to `README.md`, the file containing that doctest. Before Edition 2024, the equivalent path was resolved relative to the Rust source file that performed the outer `include_str!`.

This is a source-location rule, so it is best verified in a real fixture with the referenced files rather than pretending a standalone code block can provide those files.

## Migration Checklist

1. Set the crate to Edition 2024 and run `cargo test --doc`.
2. Fix doctests that assert exact `Location` or `type_name` values if merged source layout changes them.
3. Add `standalone_crate` only where separate compilation is actually required and not already inferred by rustdoc.
4. Recheck macros used in doctests, especially definitions involving `$crate`.
5. Update nested include paths in included Markdown so they are relative to the file containing the doctest.

## Lints

```rust
#![warn(clippy::needless_doctest_main)]

/// ```
/// // rustdoc supplies the wrapper for ordinary snippets; an explicit
/// // `fn main()` is usually unnecessary.
/// let value = 2 + 2;
/// assert_eq!(value, 4);
/// ```
pub fn example() {}

fn main() {}
```

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hiding setup code with `#`
- [doc-question-mark](./doc-question-mark.md) - Using `?` in examples
- [doc-include-str](./doc-include-str.md) - `include_str!` documentation patterns

## References

- [Rust Edition Guide: rustdoc combined tests](https://doc.rust-lang.org/edition-guide/rust-2024/rustdoc-doctests.html)
- [Rust Edition Guide: nested include change](https://doc.rust-lang.org/edition-guide/rust-2024/rustdoc-nested-includes.html)
- [rustdoc book: documentation tests](https://doc.rust-lang.org/rustdoc/write-documentation/documentation-tests.html)
