# doc-test-edition-2024

> Edition 2024 changes for doc tests: combined binary, `standalone_crate`, nested includes, and `$crate`

## Why It Matters

Rust Edition 2024 compiles all doc tests in a single binary instead of
one per doc test. This improves compilation speed and test parallelism,
but introduces subtle breaking changes:

- `Location::caller()` and `type_name` values change
- `$crate` in doc tests may resolve differently
- Nested `include_str!` paths resolve relative to the outermost file
- Some doc tests that accidentally relied on separate compilation may break

## Key Changes

| Change | Impact |
|--------|--------|
| **Combined binary** | All doc tests share one compilation unit |
| **`$crate` resolution** | Refers to the crate being documented (correct in most cases) |
| **`Location::caller()`** | File/line values point to the combined test, not the doc comment |
| **`type_name`** | Values may differ due to unification |
| **Nested include paths** | `include_str!` inside a doc `include_str!` resolves relative to the outer file |

## standalone_crate Tag

If a doc test must compile as its own crate (e.g., `#![no_std]`,
`extern crate`, or tests relying on `Location` values), use the
`standalone_crate` language tag:

```rust
/// # Examples
///
/// ```standalone_crate
/// #![no_std]
/// #![no_main]
///
/// // This compiles as its own binary crate
/// #[panic_handler]
/// fn panic(_: &core::panic::PanickInfo) -> ! {
///     loop {}
/// }
/// ```
```

```rust
/// ```standalone_crate
/// extern crate my_crate;
///
/// // Tests that require explicit crate linkage
/// use my_crate::some_item;
/// ```
```

### When to Use standalone_crate

| Condition | Example |
|-----------|---------|
| `#![no_std]` or `#![no_main]` | Embedded or kernel tests |
| `extern crate` declarations | Crate-style imports |
| `Location::caller()` sensitivity | Tests checking file/line values |
| Unique `type_name` values needed | Type introspection tests |
| `$crate` resolution issues | Macros that use `$crate` in doc tests |

## `$crate` in Doc Tests

In Edition 2024 combined mode, `$crate` in doc tests resolves to the
crate being documented. This is the correct behavior in most cases, but
may break tests that previously relied on `$crate` being unavailable
or resolving to something else.

```rust
// Before (Edition 2021): $crate was not available in doc tests
// After (Edition 2024): $crate resolves to the documented crate

/// ```rust
/// assert_eq!($crate::VERSION, "1.0.0");
/// ```
```

If you need the old behavior, use `standalone_crate`.

## Nested include_str Paths

When a `#[doc = include_str!("...")]` file itself contains `include_str!`,
the path resolves **relative to the outermost file** from Rust 2024 onward.

```rust
// lib.rs
//! # My Crate
#![doc = include_str!("../README.md")]

// README.md
// ## Quick Start
// ```rust
// # use my_crate::*;
// // ...
// ```
// #[doc = include_str!("examples/basic.rs")]  ← resolves relative to README.md
```

Previously (Edition 2021), nested includes resolved relative to `lib.rs`.

**Migration**: Move shared examples to the `examples/` directory and use
paths relative to the outermost file.

## Migration Checklist

1. **Run your tests**: `cargo test --doc` with `edition = "2024"`
2. **Check `$crate` usage**: Update macros that reference `$crate` in doc tests
3. **Check `Location`/`type_name`**: Update tests that assert specific values
4. **Apply `standalone_crate`** where needed: `#![no_std]`, `extern crate`, etc.
5. **Update nested `include_str!` paths**: Relative to outermost file now
6. **Remove unnecessary `fn main()` wrappers**: `needless_doctest_main` lint

## Lints

```rust
#![warn(clippy::needless_doctest_main)]
```

The `needless_doctest_main` clippy lint catches doc tests wrapping code
in an unnecessary `fn main() { }` — which is especially common in
Edition 2024 combined mode.

## See Also

- [doc-examples-section](./doc-examples-section.md) - Writing examples
- [doc-hidden-setup](./doc-hidden-setup.md) - Hiding setup code with #
- [doc-question-mark](./doc-question-mark.md) - Using ? in examples
- [doc-include-str](./doc-include-str.md) - include_str patterns
- [name-feature](./name-feature.md) - Feature naming conventions
