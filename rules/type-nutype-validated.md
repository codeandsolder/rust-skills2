# type-nutype-validated

> Use `nutype` for validated newtypes

**Rule**: `type-nutype-validated`

## Why It Matters

Manually implementing validated newtypes requires 40–60 lines of boilerplate: a wrapper struct, a constructor with validation, `TryFrom`, `Display`, `AsRef`, `Deref`, `Debug`, `Clone`, serde support, and tests. The `nutype` crate (v0.7.0+) generates all of this from a single attribute, eliminating entire categories of bugs while keeping the API surface clean.

This is the "parse, don't validate" pattern at its most ergonomic: the type guarantees invariants hold, and `nutype` handles construction, sanitization, serialization, and error types automatically.

## Bad

```rust
// ~50 lines of boilerplate for every validated newtype
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Username(String);

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum UsernameError {
    #[error("username too short")]
    TooShort,
    #[error("username contains invalid characters")]
    InvalidChars,
}

impl Username {
    pub fn new(s: &str) -> Result<Self, UsernameError> {
        let s = s.trim().to_lowercase();
        if s.len() < 3 {
            return Err(UsernameError::TooShort);
        }
        if !s.chars().all(|c| c.is_alphanumeric() || c == '_') {
            return Err(UsernameError::InvalidChars);
        }
        Ok(Username(s))
    }
}

impl AsRef<str> for Username {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl std::ops::Deref for Username {
    type Target = str;
    fn deref(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Username {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl std::str::FromStr for Username {
    type Err = UsernameError;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Username::new(s)
    }
}

impl serde::Serialize for Username {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(serializer)
    }
}

impl<'de> serde::Deserialize<'de> for Username {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        Username::new(&s).map_err(serde::de::Error::custom)
    }
}
```

## Good

```rust
use nutype::nutype;

#[nutype(
    validate(predicate = |s| s.len() >= 3 && s.chars().all(|c| c.is_alphanumeric() || c == '_')),
    sanitize(with = |s| s.trim().to_lowercase()),
    derive(Debug, Clone, PartialEq, Eq, Hash, Display, AsRef, Deref, FromStr),
    serde(Serialize, Deserialize),
)]
pub struct Username(String);

// That's it. Everything from the "Bad" example is generated:
//   - Username::new("  Alice_42  ") -> Ok(Username("alice_42"))
//   - Username::new("ab") -> Err(UsernameError::Invalid)
//   - format!("{username}"), username.as_ref(), *username
//   - "hello".parse::<Username>()
//   - serde_json::to_string(&username), serde_json::from_str(...)
```

## Common Patterns

```rust
use nutype::nutype;

// Non-empty string with sanitization
#[nutype(
    validate(not_empty),
    sanitize(trim),
    derive(Debug, Clone, Display, AsRef, Deref),
)]
pub struct Name(String);

// Email with regex validation
#[nutype(
    validate(regex = r"^[^@]+@[^@]+\.[^@]+$"),
    sanitize(trim, lowercase),
    derive(Debug, Clone, Display, AsRef),
    serde(Deserialize),
)]
pub struct Email(String);

// Bounded numeric
#[nutype(
    validate(greater_or_equal = 0.0, less_or_equal = 100.0),
    derive(Debug, Clone, Copy, PartialEq, PartialOrd),
)]
pub struct Percentage(f64);

// Positive integer with NonZero-size niche opt
#[nutype(
    validate(greater = 0),
    derive(Debug, Clone, Copy, PartialEq, Eq, Hash),
)]
pub struct Age(u16);
```

## Error Type

`nutype` generates a custom error enum for each validated type. For `predicate` validators, the error variant is `Invalid`. For built-in validators (`not_empty`, `greater`, `regex`, etc.), each gets its own named variant.

```rust
let err = Username::new("ab").unwrap_err();
// UsernameError::Invalid — the predicate returned false

// You can match on the error to give user-friendly messages
match err {
    UsernameError::Invalid => "Invalid username format",
}
```

## Integration with `api-parse-dont-validate`

Nutype newtypes shine at system boundaries (CLI args, HTTP requests, file parsing):

```rust
#[nutype(validate(regex = r"^\d{3}-\d{3}-\d{4}$"), derive(Debug, Clone, Display))]
pub struct Phone(String);

// Parse once at the boundary, use the validated type everywhere
fn handle_request(phone: Phone) -> Result<(), Error> {
    // phone is guaranteed valid
    lookup_phone(&phone);
    Ok(())
}
```

## See Also

- [type-newtype-validated](./type-newtype-validated.md) — Manual validated newtypes
- [type-newtype-ids](./type-newtype-ids.md) — ID newtypes
- [api-parse-dont-validate](./api-parse-dont-validate.md) — Parse at boundaries
- [type-derive-more-boilerplate](./type-derive-more-boilerplate.md) — `derive_more` for lighter boilerplate
- [nutype on GitHub](https://github.com/greyblake/nutype)
