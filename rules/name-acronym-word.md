# name-acronym-word

> In `UpperCamelCase`, treat acronyms as ordinary words: `HttpServer`, `Uuid`, `TcpStream`

## Why It Matters

Rust's naming convention treats acronyms and contractions as words when forming `UpperCamelCase`. That gives predictable word boundaries and matches the standard library: `TcpStream`, `UdpSocket`, `IpAddr`, `Ipv4Addr`, `TypeId`.

In `snake_case`, acronym words are simply lowercase: `parse_json`, `http_status`, `user_id`.

This is a casing convention, not a rule that every abbreviation must be expanded or that every identifier must avoid single-letter domain terms.

## UpperCamelCase

```rust
struct HttpServer;
struct TcpIpConnection;
struct JsonParser;
struct XmlHttpRequest;
struct Uuid;
struct TypeId;
struct Ipv4Addr;

fn main() {
    let _ = HttpServer;
    let _ = TcpIpConnection;
    let _ = JsonParser;
    let _ = XmlHttpRequest;
    let _ = Uuid;
    let _ = TypeId;
    let _ = Ipv4Addr;
}
```

Prefer these over spellings such as `HTTPServer`, `JSONParser`, or `UUID` when you control the API.

## snake_case

```rust
fn parse_json() {}
fn connect_tcp() {}
fn generate_uuid() {}
fn fetch_http_status() {}

fn main() {
    parse_json();
    connect_tcp();
    generate_uuid();
    fetch_http_status();
}
```

Do not preserve all-caps acronym spelling inside a `snake_case` identifier.

## Standard-Library Shapes

The standard library provides useful examples of the convention:

```text
std::net::TcpStream
std::net::TcpListener
std::net::UdpSocket
std::net::IpAddr
std::net::Ipv4Addr
std::any::TypeId
std::io::IoSlice
```

These are examples of names, not code that should be pasted as standalone expressions.

## Numbers Stay Part of the Word

Names such as `Utf8`, `Ipv4`, and `Base64` naturally combine letters and digits:

```rust
struct Utf8Decoder;
struct Ipv6Route;
struct Base64Encoder;

fn main() {
    let _ = Utf8Decoder;
    let _ = Ipv6Route;
    let _ = Base64Encoder;
}
```

Do not mechanically turn these into `UTF8Decoder`, `IPV6Route`, or `BASE64Encoder`.

## Single-Letter Domain Prefixes Can Still Be Valid

The acronym-as-word rule does not imply that every single-letter term must become a lowercase word. Standard names such as `CString` and `CStr` represent the established term “C string”:

```rust
use std::ffi::{CStr, CString};

fn main() {
    let value = CString::new("hello").unwrap();
    let borrowed: &CStr = value.as_c_str();
    assert_eq!(borrowed.to_bytes(), b"hello");
}
```

Follow established domain terminology and nearby APIs rather than applying acronym normalization mechanically.

## Clippy Enforcement

Enable Clippy's style lint in `Cargo.toml` if you want automated enforcement:

```toml
[lints.clippy]
upper_case_acronyms = "warn"
```

Clippy also supports a more aggressive mode in **`clippy.toml`** (or `.clippy.toml`):

```toml
upper-case-acronyms-aggressive = true
```

The aggressive option makes the lint trigger on more adjacent-uppercase cases. It is not a nested `[lints.rust]` setting in `.cargo/config.toml`.

## Public Compatibility Matters

Renaming `HTTPServer` to `HttpServer` is a breaking API change. Clippy's style guidance should not be used to churn an established public API without a migration plan. For new APIs, choose conventional casing from the start.

## Practical Guidance

- In `UpperCamelCase`, write acronym words like ordinary words: `Http`, `Json`, `Uuid`, `Tcp`.
- In `snake_case`, lowercase them normally: `http`, `json`, `uuid`, `tcp`.
- Keep numbers naturally attached: `Utf8`, `Ipv4`, `Base64`.
- Preserve established domain terms such as `CStr` when they are the conventional name.
- Put `upper-case-acronyms-aggressive` in `clippy.toml` if you opt into aggressive Clippy enforcement.
- Avoid gratuitous renames of already-public APIs solely for style.

## See Also

- [name-types-camel](./name-types-camel.md) - Type naming conventions
- [name-funcs-snake](./name-funcs-snake.md) - Function naming conventions
- [name-consts-screaming](./name-consts-screaming.md) - Constant naming
