# name-word-order

> Name error types verb-object: `ParseIntError`, not `IntParseError`

## Why It Matters

Rust convention places the verb or action first in compound names for error types and other domain entities. `ParseIntError` reads as "error while parsing int" — the action (parsing) comes first. `IntParseError` reads ambiguously as "int parse error" or "error belonging to IntParse". Consistent word order improves scannability and follows standard library patterns.

## Bad

```rust
// Verb-object swapped - reads awkwardly
struct IntParseError;
struct StringConversionError;  // ConversionStringError would be worse, but
struct HttpServerError;        // ServerHttpError is confusing

// Inconsistent ordering in a crate
enum DataError {
    FileNotFound,
    NetworkTimeout,
    SerializationError,  // Action verb after noun
}
```

## Good

```rust
// Verb-object order: action first
struct ParseIntError;        // "error while parsing int"
struct ConvertStringError;   // "error while converting string"
struct ServeHttpError;       // "error while serving HTTP"

// Standard library examples follow this pattern
use std::num::ParseIntError;
use std::num::ParseFloatError;
use std::str::ParseBoolError;
use std::char::ParseCharError;
use std::net::AddrParseError;

// Consistent crate-internal ordering
enum DataError {
    FileNotFound,
    NetworkTimeout,
    SerializeError,   // Action verb first
}
```

## Domain Entities

The same principle applies to non-error types:

```rust
// Verb-object order for domain operations
struct HttpServer;             // Not ServerHttp
struct TcpListener;            // Not ListenerTcp
struct DataProcessor;          // Not ProcessorData
struct FileReader;             // Not ReaderFile
struct LogWriter;              // Not WriterLog
```

## Decision Guide

| Pattern | Example | Correct? |
|---------|---------|----------|
| Verb-Noun | `ParseIntError` | ✅ Correct |
| Noun-Verb | `IntParseError` | ❌ Wrong |
| Modifier-Noun | `HttpServer` | ✅ Correct |
| Noun-Modifier | `ServerHttp` | ❌ Wrong |

The general rule: **action/operation first, then the thing it acts on or produces.**

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Use thiserror for library error types
- [err-custom-type](./err-custom-type.md) — Define custom error types
- [name-types-camel](./name-types-camel.md) — UpperCamelCase for type names

## References

- [Rust API Guidelines: C-WORD-ORDER](https://rust-lang.github.io/api-guidelines/naming.html#c-word-order)
- [RFC 0344: Conventions Galore](https://rust-lang.github.io/rfcs/0344-conventions-galore.html)
