# type-no-stringly

> Avoid stringly-typed APIs

**Rule**: `type-no-stringly`

## Why It Matters

Strings accept any value — typos, wrong formats, invalid data all compile fine. Enums, newtypes, and validated types catch errors at compile time or construction time, not runtime. They also provide better IDE support, documentation, and make invalid states unrepresentable.

## Bad

```rust
// Status as string — easy to get wrong
fn set_status(status: &str) {
    match status {
        "pending" => { /* ... */ }
        "active" => { /* ... */ }
        "completed" => { /* ... */ }
        _ => panic!("Unknown status"),  // Runtime error
    }
}

// Easy to misuse
set_status("pending");   // OK
set_status("Pending");   // Runtime error — wrong case
set_status("aktive");    // Runtime error — typo
set_status("done");      // Runtime error — wrong word

// Configuration as strings — no type safety, no validation
fn configure(key: &str, value: &str) { }
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// Status as enum — compile-time safety
enum Status { Pending, Active, Completed }

fn set_status(status: Status) {
    match status {
        Status::Pending => { /* ... */ }
        Status::Active => { /* ... */ }
        Status::Completed => { /* ... */ }
    }  // Exhaustive — compiler checks all cases
}

// Can only pass valid values
set_status(Status::Pending);  // OK
// set_status("aktive");      // Compile error — wrong type!

// Configuration with typed builder
struct Config {
    timeout: Duration,
    retries: u32,
    mode: Mode,
}

enum Mode { Fast, Safe, Balanced }
```

## Parsing at Boundaries with `FromStr`

```rust
use std::str::FromStr;

#[derive(Debug, Clone, Copy)]
enum Priority { Low, Medium, High }

impl FromStr for Priority {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "low" => Ok(Priority::Low),
            "medium" | "med" => Ok(Priority::Medium),
            "high" => Ok(Priority::High),
            _ => Err(ParseError::UnknownPriority(s.to_string())),
        }
    }
}

// Parse once at boundary, use typed value everywhere
fn handle_request(priority_str: &str) -> Result<(), Error> {
    let priority: Priority = priority_str.parse()?;
    // From here, priority is type-safe
    process(priority);
    Ok(())
}
```

## Reduce Boilerplate with `derive_more::FromStr`

For string-backed newtypes, `derive_more::FromStr` auto-generates the `FromStr` implementation:

```rust
use derive_more::FromStr;
use std::str::FromStr;

#[derive(Debug, Clone, FromStr)]
#[from_str(forward)]
pub struct Username(String);

// FromStr impl is auto-generated from String::from_str
let name: Username = "alice".parse()?;
```

## Validated Newtypes

```rust
// Instead of passing raw strings, use a validated newtype
struct Email(String);

impl Email {
    fn new(s: &str) -> Result<Self, ValidationError> {
        if is_valid_email(s) {
            Ok(Email(s.to_string()))
        } else {
            Err(ValidationError::InvalidEmail)
        }
    }
}

// String-free IDs
struct UserId(uuid::Uuid);

// String-free paths
struct ConfigPath(PathBuf);
```

## `cfg_select!` for Compile-Time String-Free Config (Rust 1.95+)

For compile-time configuration selection, `cfg_select!` replaces string-based platform detection:

```rust
use core::cfg_select;

// Compile-time config — no strings at runtime
const BUFFER_SIZE: usize = cfg_select! {
    target_os = "linux"   => 65536,
    target_os = "macos"   => 4096,
    target_os = "windows" => 8192,
    _ => 1024,
};

// Deserialization strategy — selected at compile time
const PARSER: ParserKind = cfg_select! {
    feature = "json"    => ParserKind::Json,
    feature = "toml"    => ParserKind::Toml,
    feature = "yaml"    => ParserKind::Yaml,
    _ => ParserKind::Json,
};
```

## With Serde

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum EventType {
    UserCreated,
    UserDeleted,
    UserUpdated,
}

// JSON: {"type": "user_created", ...}
// Automatically validated during deserialization
```

## See Also

- [anti-stringly-typed](./anti-stringly-typed.md) — Anti-pattern details
- [type-newtype-validated](./type-newtype-validated.md) — Validated newtypes
- [type-enum-states](./type-enum-states.md) — Enums for states
- [type-derive-more-boilerplate](./type-derive-more-boilerplate.md) — `derive_more` for boilderplate reduction
- [type-nutype-validated](./type-nutype-validated.md) — `nutype` for validated newtypes
