# name-types-camel

> Use `UpperCamelCase` for structs, enums, traits, type aliases, and other type-level names

## Why It Matters

Rust's type-level naming convention is `UpperCamelCase`. The built-in `non_camel_case_types` lint warns by default, and following the convention makes type names visually distinct from functions, variables, and modules.

## Bad

```rust
#![allow(non_camel_case_types)]

struct http_client {
    connected: bool,
}

trait serializable {
    fn encode(&self) -> String;
}

enum response_type {
    Ok,
    Error,
}

fn main() {
    let _ = http_client { connected: true };
    let _ = response_type::Ok;
}
```

Suppressing the lint makes the code legal but needlessly diverges from normal Rust style.

## Good

```rust
struct HttpClient {
    connected: bool,
}

trait Serializable {
    fn encode(&self) -> String;
}

enum ResponseType {
    Ok,
    Error,
}

impl Serializable for HttpClient {
    fn encode(&self) -> String {
        self.connected.to_string()
    }
}

fn main() {
    let client = HttpClient { connected: true };
    assert_eq!(client.encode(), "true");

    let response = ResponseType::Ok;
    assert!(matches!(response, ResponseType::Ok));
    let _also_valid = ResponseType::Error;
}
```

The same convention applies to generic user-defined types and type aliases.

## Acronyms Are Usually Treated as Words

```rust
struct HttpServer;
struct JsonParser;
struct TcpStream;
struct IoError;
struct Uuid([u8; 16]);

fn main() {
    let _ = HttpServer;
    let _ = JsonParser;
    let _ = TcpStream;
    let _ = IoError;
    let _ = Uuid([0; 16]);
}
```

Prefer spellings such as `HttpServer`, `JsonParser`, `TcpStream`, `IoError`, and `Uuid` over `HTTPServer`, `JSONParser`, `TCPStream`, `IOError`, and `UUID` when naming ordinary Rust types.

Preserve a project's established public terminology when there is a stronger compatibility reason; naming conventions should improve consistency, not cause pointless API churn.

## Type Aliases

```rust
use std::future::Future;
use std::pin::Pin;

type BoxedFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;
type AppResult<T> = Result<T, String>;

fn parse_number(input: &str) -> AppResult<u32> {
    input.parse().map_err(|err| format!("{err}"))
}

fn main() {
    assert_eq!(parse_number("42").unwrap(), 42);
    let _: Option<BoxedFuture<'static, ()>> = None;
}
```

Aliases are type-level names too, so use `UpperCamelCase` rather than `boxed_future` or `app_result`.

## Generic Parameter Names Are Different

The type itself uses `UpperCamelCase`; generic type parameters are conventionally short uppercase identifiers such as `T`, `E`, `K`, and `V`, or descriptive `UpperCamelCase` names when clarity benefits:

```rust
struct Pair<Key, Value> {
    key: Key,
    value: Value,
}

fn main() {
    let pair = Pair {
        key: "answer",
        value: 42,
    };
    assert_eq!(pair.key, "answer");
    assert_eq!(pair.value, 42);
}
```

Do not define fake replacements for standard names such as `HashMap` or `Result` merely to demonstrate casing; examples should use realistic user-defined types.

## Generated/Foreign Names Are Exceptions

FFI generators, schema-generated APIs, and compatibility layers sometimes must preserve an external spelling. Suppress the lint locally for that boundary rather than normalizing the entire crate around foreign casing.

## See Also

- [name-funcs-snake](./name-funcs-snake.md) — value-level names
- [name-variants-camel](./name-variants-camel.md) — enum variants
- [name-acronym-word](./name-acronym-word.md) — acronym handling

## References

- [Rust API Guidelines: naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [non_camel_case_types lint](https://doc.rust-lang.org/rustc/lints/listing/warn-by-default.html#non-camel-case-types)
