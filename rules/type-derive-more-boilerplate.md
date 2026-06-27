# type-derive-more-boilerplate

> Use `derive_more` for newtype boilerplate reduction

**Rule**: `type-derive-more-boilerplate`

## Why It Matters

Newtypes are one of Rust's most powerful type-safety tools, but they require significant boilerplate: `From`/`Into` for the inner type, `AsRef`, `Deref`, `Display`, `FromStr`, and sometimes `IntoIterator`. The `derive_more` crate eliminates this boilerplate with a single `#[derive(...)]` line per newtype, reducing 15–25 lines of manual trait impls to a single attribute. This lowers the friction of creating newtypes and makes it practical to use them pervasively.

## Bad

```rust
// 20+ lines of boilerplate for one newtype
pub struct Email(String);

impl From<String> for Email {
    fn from(s: String) -> Self {
        Email(s)
    }
}

impl AsRef<str> for Email {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl std::ops::Deref for Email {
    type Target = str;
    fn deref(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Email {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl std::str::FromStr for Email {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(Email(s.to_string()))
    }
}

// And if this wraps a collection:
pub struct EmailList(Vec<Email>);

impl IntoIterator for EmailList {
    type Item = Email;
    type IntoIter = std::vec::IntoIter<Email>;
    fn into_iter(self) -> Self::IntoIter {
        self.0.into_iter()
    }
}
```

## Good

```rust
use derive_more::{
    AsRef, Deref, Display, From, FromStr, IntoIterator,
};

#[derive(Debug, Clone, From, AsRef, Deref, Display, FromStr)]
pub struct Email(String);

// All six trait impls in one line. Each trait is generated
// with the correct implementation for a single-field newtype:
//   - From<String> for Email
//   - AsRef<str> for Email (delegates to String::as_ref)
//   - Deref<Target = str> (calls String::deref)
//   - Display (delegates to String::fmt)
//   - FromStr (parses String, wraps in Email)

// For collection wrappers:
#[derive(Debug, Clone, IntoIterator)]
pub struct EmailList(Vec<Email>);

// IntoIterator generated automatically — iterates over Vec<Email>
```

## Available Derive Macros

| Derive | Generates | Use Case |
|--------|-----------|----------|
| `From` | `From<T>` for each field's type | Wrapping inner value |
| `AsRef` | `AsRef<T>` for the inner type | Borrowing inner value |
| `Deref` | `Deref<Target = T>` | Accessing inner methods |
| `Display` | `Display` formatting | String representation |
| `FromStr` | `FromStr` with `ParseError` | Parsing from strings |
| `IntoIterator` | `IntoIterator` for collections | Iterating over inner collection |
| `Into` | `Into<T>` | Unwrapping (less common) |
| `Add`, `Sub`, `Mul`, `Div`, etc. | Arithmetic operators | Numeric newtypes |
| `Constructor` | `new()` method | Named constructor |
| `Debug` (re-exported from std) | Debug formatting | Printing |

## Complete Example

```rust
use derive_more::{AsRef, Deref, Display, From, FromStr};

#[derive(Debug, Clone, PartialEq, Eq, Hash, From, AsRef, Deref, Display, FromStr)]
pub struct Username(String);

// Usage:
let name = Username::from("alice".to_string());
let copy: String = name.0;                  // Field access (or use Into)
println!("{name}");                          // Display
let s: &str = name.as_ref();                 // AsRef
let s: &str = &name;                         // Deref (via auto-deref)
let parsed: Username = "bob".parse()?;       // FromStr
```

## Numeric Newtypes

```rust
use derive_more::{Add, AddAssign, Display, From, Mul};

#[derive(Debug, Clone, Copy, PartialEq, From, Add, AddAssign, Mul, Display)]
pub struct Meters(f64);

let a = Meters(10.0);
let b = Meters(20.0);
let c = a + b;           // Add
let d = a * 2.0;         // Mul
println!("{d}");          // Display — "40"

// Without derive_more: four manual trait impls (Add, AddAssign, Mul, Display)
```

## See Also

- [type-newtype-ids](./type-newtype-ids.md) — ID newtypes
- [type-newtype-validated](./type-newtype-validated.md) — Validated newtypes
- [type-nutype-validated](./type-nutype-validated.md) — `nutype` for validated newtypes with validation built-in
- [type-newtype-repr-transparent](./type-newtype-repr-transparent.md) — Always `#[repr(transparent)]`
- [derive_more docs](https://docs.rs/derive_more/latest/derive_more/)
