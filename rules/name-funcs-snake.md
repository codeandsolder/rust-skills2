# name-funcs-snake

> Use `snake_case` for functions, methods, variables, and modules

## Why It Matters

Rust's conventional value-level names use `snake_case`. The built-in naming lints warn about non-snake-case functions, methods, variables, and modules by default, and ecosystem code overwhelmingly follows the convention.

Consistent casing makes roles easy to scan: `HttpClient` looks like a type while `send_request` looks like an operation.

## Bad

```rust
#![allow(dead_code)]

#[allow(non_snake_case)]
fn calculateTotal(values: &[u32]) -> u32 {
    values.iter().sum()
}

fn main() {
    assert_eq!(calculateTotal(&[1, 2, 3]), 6);
}
```

The function can be made legal by suppressing the lint, but the spelling fights normal Rust style for no semantic benefit.

## Good

```rust
fn calculate_total(values: &[u32]) -> u32 {
    values.iter().sum()
}

struct User {
    first_name: String,
    last_name: String,
    active: bool,
}

impl User {
    fn full_name(&self) -> String {
        format!("{} {}", self.first_name, self.last_name)
    }

    fn is_active(&self) -> bool {
        self.active
    }
}

mod user_service {
    pub fn max_connections() -> usize {
        100
    }
}

fn main() {
    let user_count = calculate_total(&[1, 2, 3]);
    assert_eq!(user_count, 6);

    let user = User {
        first_name: "Ada".into(),
        last_name: "Lovelace".into(),
        active: true,
    };
    assert_eq!(user.full_name(), "Ada Lovelace");
    assert!(user.is_active());
    assert_eq!(user_service::max_connections(), 100);
}
```

The same convention applies to ordinary local bindings and module names.

## Acronyms in `snake_case`

Treat acronyms as words instead of preserving all-capitals spelling:

```rust
fn parse_json(input: &str) -> bool {
    input.starts_with('{')
}

fn connect_tcp(host: &str) -> String {
    format!("tcp://{host}")
}

fn generate_uuid() -> &'static str {
    "00000000-0000-0000-0000-000000000000"
}

fn main() {
    let http_response = "ok";
    let json_data = "{}";

    assert_eq!(http_response, "ok");
    assert!(parse_json(json_data));
    assert_eq!(connect_tcp("localhost"), "tcp://localhost");
    assert_eq!(generate_uuid().len(), 36);
}
```

Prefer `parse_json`, `connect_tcp`, and `http_response`, not `parse_JSON`, `connect_TCP`, or `HTTP_response`.

## Names Should Still Be Specific

Casing is only the mechanical part of naming. `process_data` can be valid `snake_case` and still be vague. Prefer names that communicate the operation and domain when that distinction matters:

```rust
fn decode_utf8(bytes: &[u8]) -> Result<&str, std::str::Utf8Error> {
    std::str::from_utf8(bytes)
}

fn main() {
    assert_eq!(decode_utf8(b"hello").unwrap(), "hello");
}
```

Do not contort names merely to avoid a lint; use standard casing while preserving the terminology your domain actually uses.

## Generated/Foreign Names Are Exceptions

FFI bindings, protocol-generated code, macro-generated APIs, and names that must match an external ABI/schema may need non-Rust casing. Keep lint suppressions narrow and document why the external name must be preserved rather than weakening naming lints across an entire crate.

## See Also

- [name-types-camel](./name-types-camel.md) — type naming
- [name-consts-screaming](./name-consts-screaming.md) — constants/statics
- [name-lifetime-short](./name-lifetime-short.md) — lifetime parameters
- [name-acronym-word](./name-acronym-word.md) — acronym spelling

## References

- [Rust API Guidelines: naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [non_snake_case lint](https://doc.rust-lang.org/rustc/lints/listing/warn-by-default.html#non-snake-case)
