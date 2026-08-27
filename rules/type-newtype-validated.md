# type-newtype-validated

> Put durable domain invariants behind checked constructors so downstream code can rely on the type instead of re-validating primitives

**Rule**: `type-newtype-validated`

## Why It Matters

A validation function that returns `bool` leaves the caller holding the same weakly typed value. A validated newtype records the successful check in the type: safe code cannot construct the value without going through an invariant-preserving boundary.

This is most valuable when the property survives across multiple calls or layers of the program. For a one-off local condition, a plain check is often clearer.

## Bad: Validate but Keep the Primitive

```rust
fn is_valid_username(value: &str) -> bool {
    value.len() >= 3 && value.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn greet(username: &str) -> String {
    // Must trust that somebody validated this earlier.
    format!("hello {username}")
}

fn main() {
    let raw = "alice_42";
    assert!(is_valid_username(raw));
    assert_eq!(greet(raw), "hello alice_42");
}
```

## Good: Close Construction Around the Invariant

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Username(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvalidUsername;

impl Username {
    pub fn parse(raw: &str) -> Result<Self, InvalidUsername> {
        let value = raw.trim().to_lowercase();
        let valid = value.len() >= 3
            && value.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');

        valid.then_some(Self(value)).ok_or(InvalidUsername)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

fn greet(username: &Username) -> String {
    format!("hello {}", username.as_str())
}

fn main() {
    let username = Username::parse("  Alice_42 ").unwrap();
    assert_eq!(greet(&username), "hello alice_42");
    assert!(Username::parse("!!").is_err());
}
```

Keep the field private and avoid unrestricted mutable access to the representation. Otherwise safe callers can invalidate the guarantee after construction.

## Use `NonZero` for the Common Non-Zero Integer Invariant

```rust
use core::num::NonZero;

#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkerCount(NonZero<u32>);

impl WorkerCount {
    pub fn new(value: u32) -> Option<Self> {
        NonZero::new(value).map(Self)
    }

    pub fn get(self) -> u32 {
        self.0.get()
    }
}

fn main() {
    assert!(WorkerCount::new(0).is_none());
    assert_eq!(WorkerCount::new(8).unwrap().get(), 8);
}
```

Do not hand-roll validation when the standard library already has a type that precisely represents the invariant.

## `nutype` 0.7 for Repetitive Validated-Newtype APIs

`nutype` can generate sanitization, validation, conversion, display, and serde support. Validation changes the constructor to `try_new`.

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, len_char_max = 64),
    derive(Debug, Clone, PartialEq, Eq, Display, AsRef, FromStr, Serialize, Deserialize),
)]
pub struct Username(String);

fn main() {
    let username = Username::try_new("  Alice  ").unwrap();
    assert_eq!(username.as_ref(), "alice");
    assert!(Username::try_new("   ").is_err());

    let encoded = serde_json::to_string(&username).unwrap();
    let decoded: Username = serde_json::from_str(&encoded).unwrap();
    assert_eq!(decoded, username);
}
```

With `nutype` 0.7, request serde traits through `derive(Serialize, Deserialize)` and enable the crate's `serde` feature. Older-looking `serde(...)` attribute syntax is not the current API.

Use a hand-written newtype when the invariant/API is small or highly custom; proc-macro convenience is not itself a reason to add a dependency.

## Manual Serde Must Re-Establish the Invariant

If a manual newtype is deserialized from an untrusted representation, route deserialization through the checked constructor rather than constructing the field directly.

```rust
use serde::{Deserialize, Deserializer, Serialize};
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Email(String);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmailError;

impl fmt::Display for EmailError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("invalid email address")
    }
}

impl Email {
    pub fn parse(raw: String) -> Result<Self, EmailError> {
        if raw.contains('@') && !raw.starts_with('@') && !raw.ends_with('@') {
            Ok(Self(raw))
        } else {
            Err(EmailError)
        }
    }
}

impl<'de> Deserialize<'de> for Email {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let raw = String::deserialize(deserializer)?;
        Email::parse(raw).map_err(serde::de::Error::custom)
    }
}

fn main() {
    let email: Email = serde_json::from_str(r#""user@example.com""#).unwrap();
    assert_eq!(email.0, "user@example.com");
    assert!(serde_json::from_str::<Email>(r#""not-an-email""#).is_err());
}
```

Serde derives or custom implementations are alternate construction paths. They must preserve the same invariant as ordinary constructors.

## Sanitization Is a Domain Decision

Trimming or normalizing case can be correct for some identifiers and wrong for others. Treat sanitization as part of parsing semantics, not as a generic way to make invalid input pass.

Likewise, avoid unchecked constructors unless there is a measured need and a clearly documented invariant proof at every call site.

## See Also

- [api-parse-dont-validate](./api-parse-dont-validate.md) — parse at boundaries
- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-newtype-ids](./type-newtype-ids.md) — identifier wrappers
- [type-nutype-validated](./type-nutype-validated.md) — current `nutype` API details
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — standard non-zero invariant type
