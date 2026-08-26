# name-word-order

> Keep compound names in a consistent, idiomatic word order

## Why It Matters

Rust's API Guidelines recommend consistency in the order of words in compound names. For similar error types, the standard library commonly uses **verb-object-error** names such as `ParseIntError`, `ParseBoolError`, `JoinPathsError`, and `StripPrefixError`.

The important rule is not that every Rust type must start with a verb. Use ordinary English modifier-noun order for names such as `HttpServer` and `TcpListener`, and match established terminology in the surrounding API. Prefer consistency with closely related standard-library or crate-local names over mechanically rearranging words.

## Bad

```rust
// Inconsistent names for the same kind of operation.
struct IntParseFailure;
struct FloatParsingFailure;
struct ParseBoolFailure;

// Awkward modifier order.
struct ServerHttp;
struct ListenerTcp;
```

## Good

```rust
// Consistent verb-object-error order for a family of parsing errors.
struct ParseWidgetError;
struct ParseHeaderError;
struct ParsePacketError;

// Ordinary modifier-noun names where that is the natural phrase.
struct HttpServer;
struct TcpListener;
struct DataProcessor;

// Closely related standard-library types use the same Parse*Error family.
let _: Option<std::num::ParseIntError> = None;
let _: Option<std::num::ParseFloatError> = None;
let _: Option<std::str::ParseBoolError> = None;
let _: Option<std::char::ParseCharError> = None;
```

`std::net::AddrParseError` is a historical counterexample to the otherwise common `Parse*Error` family. The API Guidelines explicitly use it to illustrate that consistency with a family can be preferable to copying an inconsistent legacy name when designing a new API.

## Decision Guide

| Situation | Prefer | Example |
|-----------|--------|---------|
| Family of operation errors | Match the family's established order | `ParseIntError`, `ParseWidgetError` |
| Modifier + noun | Natural English order | `HttpServer`, `TcpListener` |
| Existing public API family | Consistency with sibling names | `FooReader`, `FooWriter` |
| No established convention | Pick a clear order and use it consistently | crate-specific |

The guideline is **consistent word order**, not a universal grammar rule that every compound Rust name must be verb-first.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Use thiserror for library error types
- [err-custom-type](./err-custom-type.md) — Define custom error types
- [name-types-camel](./name-types-camel.md) — UpperCamelCase for type names

## References

- [Rust API Guidelines: C-WORD-ORDER](https://rust-lang.github.io/api-guidelines/naming.html#c-word-order)
- [RFC 0344: Conventions Galore](https://rust-lang.github.io/rfcs/0344-conventions-galore.html)
