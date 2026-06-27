# api-nutype-validated

> Use `nutype` (v0.7.0, `greyblake/nutype`) for sanitized and validated newtypes with zero overhead

**Rule**: `api-nutype-validated`

## Why It Matters

The "parse, don't validate" pattern requires writing boilerplate: constructor, error type, `FromStr`, `Display`, `AsRef`, `Deref`, serde impls. The `nutype` crate generates all of this from a single attribute macro. It supports sanitization (`trim`, `lowercase`, custom `with = ...`), validation (`not_empty`, `len_char_max`, `regex`, `predicate`), automatic error enums, serde integration, and `const_fn` support — making validated newtypes as ergonomic as raw primitives.

## Bad

```rust
// Manual validated newtype — 40+ lines of boilerplate
pub struct Username(String);

#[derive(Debug)]
pub enum UsernameError {
    Empty,
    TooLong(usize),
    InvalidChars,
}

impl Username {
    pub fn new(raw: String) -> Result<Self, UsernameError> {
        let trimmed = raw.trim().to_string();
        if trimmed.is_empty() {
            return Err(UsernameError::Empty);
        }
        if trimmed.len() > 20 {
            return Err(UsernameError::TooLong(trimmed.len()));
        }
        if !trimmed.chars().all(|c| c.is_alphanumeric()) {
            return Err(UsernameError::InvalidChars);
        }
        Ok(Self(trimmed))
    }
}

impl AsRef<str> for Username {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Username {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

// And still no serde, no FromStr, no Deref...
```

## Good

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, len_char_max = 20, regex = "^[a-zA-Z][a-zA-Z0-9]*$"),
    derive(Debug, Clone, Display, AsRef, Deref, FromStr, Into)
)]
pub struct Username(String);

// Automatic UsernameError enum with Empty, TooLong, RegexMismatch variants
// Username::new(String) -> Result<Username, UsernameError>
// Username::try_from(String) — auto-derived via FromStr
// serde: Serialize/Deserialize with validation on deserialize

// Usage:
let name = Username::new("  Alice_123  ".into())?;
assert_eq!(name.as_ref(), "alice_123");  // trimmed + lowercased
```

## Advanced Examples

```rust
// 1. Custom sanitizer function
fn strip_whitespace(s: String) -> String {
    s.chars().filter(|c| !c.is_whitespace()).collect()
}

#[nutype(
    sanitize(with = strip_whitespace),
    validate(not_empty),
    derive(Debug, Clone, Display)
)]
pub struct Slug(String);


// 2. Predicate-based validation
#[nutype(
    validate(predicate = |n: &u32| *n > 0 && *n <= 65535),
    derive(Debug, Clone, Copy)
)]
pub struct Port(u16);

assert!(Port::new(8080).is_ok());
assert!(Port::new(0).is_err());   // predicate fails


// 3. Serde integration with deserialization validation
#[nutype(
    sanitize(trim),
    validate(not_empty, len_char_max = 100),
    derive(Debug, Clone, Serialize, Deserialize)
)]
pub struct Email(String);

// Deserialization runs validation:
let email: Email = serde_json::from_str(r#""invalid"#)?;
// Fails if empty, too long, or not present


// 4. const_fn support for compile-time construction
#[nutype(
    validate(not_empty),
    derive(Debug, Clone),
    const_fn
)]
pub struct Label(&'static str);

// const LABEL: Label = Label::new("static").unwrap();  // const context
```

## Relationship to Other Rules

- Cross-reference with [api-parse-dont-validate](./api-parse-dont-validate.md): `nutype` is the 2026 gold-standard implementation of the "parse, don't validate" principle.
- Cross-reference with [api-newtype-safety](./api-newtype-safety.md): `nutype` automates the boilerplate for type-safe newtypes.
- Cross-reference with [api-serde-optional](./api-serde-optional.md): when using `nutype` in a library, gate it behind a feature flag.

## See Also

- [api-newtype-safety](./api-newtype-safety.md) — Type-safe newtype pattern
- [type-nutype-validated](./type-nutype-validated.md) — Nutype for validated newtypes
- [api-parse-dont-validate](./api-parse-dont-validate.md) — Parse into validated types at boundaries
- [type-newtype-validated](./type-newtype-validated.md) — Enforce validation at construction

## References

- [nutype crate](https://github.com/greyblake/nutype)
- [Parse, don't validate (Alexis King)](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [api-parse-dont-validate](./api-parse-dont-validate.md) — Parse into validated types
- [api-newtype-safety](./api-newtype-safety.md) — Newtypes for type safety
