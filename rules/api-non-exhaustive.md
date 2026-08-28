# api-non-exhaustive

> Use `#[non_exhaustive]` when a public struct, enum, or enum variant is intentionally open to compatible growth

## Why It Matters

Adding a variant to a public enum or a field to a public struct can break downstream code that matches exhaustively or constructs the type directly. `#[non_exhaustive]` changes what **other crates** may assume so the defining crate can add variants or fields later without that particular source break.

This is an API-design tradeoff, not a blanket requirement for every public type. Closed sets such as a deliberately complete three-way ordering usually should remain exhaustive.

## Bad: Promise a Closed Shape You Expect to Extend

```rust
pub enum ErrorKind {
    NotFound,
    PermissionDenied,
    TimedOut,
}

fn describe(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::NotFound => "not found",
        ErrorKind::PermissionDenied => "permission denied",
        ErrorKind::TimedOut => "timed out",
    }
}

pub struct Config {
    pub name: String,
    pub value: i32,
}

fn main() {
    let _config = Config {
        name: "demo".into(),
        value: 42,
    };
}
```

If these public definitions are in a library, downstream exhaustive matches and struct literals become commitments you must preserve or break deliberately.

## Good: Mark an Intentionally Open Type

```rust
#[non_exhaustive]
pub enum ErrorKind {
    NotFound,
    PermissionDenied,
    TimedOut,
}

#[non_exhaustive]
pub struct Config {
    pub name: String,
    pub value: i32,
}

impl Config {
    pub fn new(name: impl Into<String>, value: i32) -> Self {
        Self {
            name: name.into(),
            value,
        }
    }
}

fn downstream_style(kind: ErrorKind) -> &'static str {
    // The wildcard is required in another crate. It is accepted here as well.
    match kind {
        ErrorKind::NotFound => "not found",
        ErrorKind::PermissionDenied => "permission denied",
        ErrorKind::TimedOut => "timed out",
        _ => "other",
    }
}

fn main() {
    let _config = Config::new("demo", 42);
    let _ = downstream_style(ErrorKind::TimedOut);
}
```

Outside the defining crate:

- a `#[non_exhaustive]` enum must be matched with a wildcard arm;
- a `#[non_exhaustive]` struct cannot be constructed with a struct literal;
- a non-exhaustive struct-style enum variant must be matched with `..` and cannot be constructed directly.

Inside the defining crate, `#[non_exhaustive]` has no such effect: exhaustive matching and direct construction are still allowed. That distinction matters when writing examples; a single-crate snippet cannot prove the downstream restriction merely by naming a module "external".

## Defining-Crate Behavior

```rust
#[non_exhaustive]
pub enum Status {
    Active,
    Inactive,
}

#[non_exhaustive]
pub struct Options {
    pub retries: u8,
}

fn internal(status: Status) {
    // Exhaustive matching is legal inside the defining crate.
    match status {
        Status::Active => {}
        Status::Inactive => {}
    }

    // Direct construction is legal here too.
    let _ = Options { retries: 3 };
}

fn main() {
    internal(Status::Active);
}
```

For a real compatibility test, put the API in one crate and compile a second dependent crate. The rule corpus's single-example harness checks the defining-side syntax while the language rule itself is specified by the Rust Reference.

## Non-Exhaustive Variants

Use the attribute on one variant when the enum is otherwise closed but that variant's fields may grow:

```rust
pub enum Message {
    #[non_exhaustive]
    Error { code: u32, message: String },
    Ok(String),
}

fn defining_crate_match(message: Message) {
    match message {
        Message::Ok(data) => drop(data),
        // `..` is optional here because this is the defining crate, but writing
        // it mirrors the pattern downstream callers are required to use.
        Message::Error { code, message, .. } => {
            let _ = (code, message);
        }
    }
}

fn main() {}
```

## When to Use It

Prefer `#[non_exhaustive]` when all of these are true:

- the type is part of a public library API;
- future variants or fields are plausible;
- downstream exhaustive construction or matching would otherwise constrain compatible evolution.

Do not add it mechanically to internal types or intentionally closed public sets. It imposes real ergonomics costs on callers: wildcard matches lose exhaustiveness checking for future variants, and non-exhaustive structs need constructors or builders.

## See Also

- [api-sealed-trait](./api-sealed-trait.md) - Controlling external trait implementations
- [err-custom-type](./err-custom-type.md) - Error type design
- [api-builder-pattern](./api-builder-pattern.md) - Constructors/builders for evolving structs

## References

- [Rust Reference: `non_exhaustive`](https://doc.rust-lang.org/reference/attributes/type_system.html#the-non_exhaustive-attribute)
