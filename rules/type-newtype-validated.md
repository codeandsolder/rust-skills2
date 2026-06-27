# type-newtype-validated

> Use newtypes to enforce validation at construction

**Rule**: `type-newtype-validated`

## Why It Matters

A validated newtype guarantees its inner value is always valid. Once you have an `Email`, you know it passed validation — no re-checking needed. This "parse, don't validate" pattern catches errors at boundaries and makes invalid states unrepresentable.

## Bad

```rust
// Validation scattered throughout code
fn send_email(to: &str, body: &str) -> Result<(), Error> {
    if !is_valid_email(to) {  // Must check every time
        return Err(Error::InvalidEmail);
    }
    // ...
}

fn add_recipient(list: &mut Vec<String>, email: &str) -> Result<(), Error> {
    if !is_valid_email(email) {  // Check again
        return Err(Error::InvalidEmail);
    }
    list.push(email.to_string());
    Ok(())
}
```

## Good

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Email(String);

impl Email {
    pub fn new(s: &str) -> Result<Self, EmailError> {
        if is_valid_email(s) {
            Ok(Email(s.to_string()))
        } else {
            Err(EmailError::Invalid(s.to_string()))
        }
    }

    pub fn as_str(&self) -> &str { &self.0 }
}

// No validation needed — Email is always valid
fn send_email(to: &Email, body: &str) -> Result<(), Error> {
    send_to_address(to.as_str(), body)
}

fn add_recipient(list: &mut Vec<Email>, email: Email) {
    list.push(email);  // Already validated
}
```

## Common Validated Types

```rust
// URLs
pub struct Url(url::Url);

impl Url {
    pub fn parse(s: &str) -> Result<Self, UrlError> {
        url::Url::parse(s).map(Url).map_err(UrlError::from)
    }
}

// Non-empty strings
pub struct NonEmptyString(String);

impl NonEmptyString {
    pub fn new(s: String) -> Option<Self> {
        if s.is_empty() { None } else { Some(NonEmptyString(s)) }
    }
}

// Positive numbers
pub struct PositiveI32(i32);

impl PositiveI32 {
    pub fn new(n: i32) -> Option<Self> {
        if n > 0 { Some(PositiveI32(n)) } else { None }
    }
}

// Bounded ranges
pub struct Percentage(f64);

impl Percentage {
    pub fn new(value: f64) -> Result<Self, RangeError> {
        if (0.0..=100.0).contains(&value) {
            Ok(Percentage(value))
        } else {
            Err(RangeError::OutOfBounds)
        }
    }
}
```

## Using `core::num::NonZero<uN>` for Non-Zero Integers

For the common case of "must be non-zero", use the standard library's `NonZero` types — no custom validation needed:

```rust
use core::num::NonZero;

// NonZero encodes the "not zero" invariant in the type system
pub struct OrderId(NonZero<u64>);

impl OrderId {
    pub fn new(raw: u64) -> Option<Self> {
        Some(Self(NonZero::new(raw)?))
    }
}

// Option<OrderId> is 8 bytes — zero-cost optional
// (the zero bit pattern is the None discriminant)
```

## Using `nutype` for Ergonomic Validated Newtypes

The `nutype` crate (v0.7.0+) replaces 40–60 lines of manual boilerplate with a single attribute:

```rust
use nutype::nutype;

#[nutype(
    validate(predicate = |s| s.contains('@') && s.contains('.')),
    sanitize(trim, lowercase),
    derive(Debug, Clone, Display, AsRef, Deref, FromStr),
    serde(Deserialize),
)]
pub struct Email(String);

// One attribute generates: constructor, validation, sanitization,
// Display, AsRef, Deref, FromStr, serde Deserialize, error type.

let email = Email::new("  User@Example.COM  ").unwrap();
assert_eq!(email.as_str(), "user@example.com");  // Auto-lowercased
```

## `#[serde(try_from = "...")]` Pattern

For serde deserialization with validation, use `#[serde(try_from = "...")]` to reuse your `TryFrom` impl:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct Email(String);

// Implement TryFrom<String> / TryFrom<&str>
impl TryFrom<String> for Email {
    type Error = EmailError;
    fn try_from(s: String) -> Result<Self, Self::Error> {
        if is_valid_email(&s) {
            Ok(Email(s))
        } else {
            Err(EmailError::Invalid(s))
        }
    }
}

// Reuse TryFrom for serde deserialization
impl<'de> Deserialize<'de> for Email {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Email::try_from(s).map_err(serde::de::Error::custom)
    }
}
```

## Compile-Time Validation with `static_assertions`

For invariants that can be checked at compile time (type sizes, alignment, trait bounds), use `static_assertions`:

```rust
use static_assertions::const_assert;

// Ensure the validated type doesn't accidentally grow
const_assert!(std::mem::size_of::<Email>() == std::mem::size_of::<String>());

// Ensure alignment matches expectations
const_assert!(std::mem::align_of::<Email>() == std::mem::align_of::<String>());
```

## With Serde (Manual)

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct Email(String);

impl<'de> Deserialize<'de> for Email {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Email::new(&s).map_err(serde::de::Error::custom)
    }
}

let email: Email = serde_json::from_str(r#""user@example.com""#)?;
```

## See Also

- [api-parse-dont-validate](./api-parse-dont-validate.md) — Parse at boundaries
- [api-newtype-safety](./api-newtype-safety.md) — Type-safe distinctions
- [type-newtype-ids](./type-newtype-ids.md) — ID newtypes
- [type-nutype-validated](./type-nutype-validated.md) — `nutype` for ergonomic validated newtypes
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — `NonZero<uN>` for non-zero integers
- [type-derive-more-boilerplate](./type-derive-more-boilerplate.md) — `derive_more` for boilerplate reduction
