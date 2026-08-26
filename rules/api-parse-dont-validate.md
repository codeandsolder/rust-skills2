# api-parse-dont-validate

> Parse into validated types at boundaries

## Why It Matters

Instead of validating data and hoping you remember to check everywhere, parse it into a type that can only be constructed from valid data. The type system then guarantees validity - you can't forget to validate because invalid states are unrepresentable.

## Bad

```rust
// Validation scattered throughout codebase
fn send_email(email: &str) -> Result<(), Error> {
    // Did someone validate this already? Who knows!
    if !is_valid_email(email) {
        return Err(Error::InvalidEmail);
    }
    // Send email...
}

fn add_to_mailing_list(email: &str) -> Result<(), Error> {
    // Duplicate validation, or did we forget?
    if !is_valid_email(email) {
        return Err(Error::InvalidEmail);
    }
    // Add to list...
}

// Easy to forget validation
fn process_user_email(email: &str) {
    // Oops, no validation!
    database.store_email(email);
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
/// A validated email address.
/// Can only be constructed via `Email::parse()`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Email(String);

impl Email {
    /// Parses and validates an email address.
    pub fn parse(s: impl Into<String>) -> Result<Self, EmailError> {
        let s = s.into();
        if Self::is_valid(&s) {
            Ok(Email(s))
        } else {
            Err(EmailError::Invalid)
        }
    }
    
    fn is_valid(s: &str) -> bool {
        s.contains('@') && s.len() > 3  // Simplified
    }
    
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

// Now functions can accept Email - guaranteed valid!
fn send_email(email: &Email) -> Result<(), Error> {
    // No validation needed - Email is always valid
    smtp_send(email.as_str())
}

fn add_to_mailing_list(email: Email) {
    // No validation needed
    list.push(email);
}
```

## More Examples

```rust
// Port number (1-65535)
pub struct Port(u16);

impl Port {
    pub fn new(n: u16) -> Option<Self> {
        if n > 0 { Some(Port(n)) } else { None }
    }
    
    pub fn get(&self) -> u16 {
        self.0
    }
}

// Non-empty string
pub struct NonEmptyString(String);

impl NonEmptyString {
    pub fn new(s: impl Into<String>) -> Option<Self> {
        let s = s.into();
        if s.is_empty() { None } else { Some(Self(s)) }
    }
}

// Positive integer
pub struct PositiveI32(i32);

impl PositiveI32 {
    pub fn new(n: i32) -> Option<Self> {
        if n > 0 { Some(Self(n)) } else { None }
    }
}

// Bounded value
pub struct Percentage(u8);

impl Percentage {
    pub fn new(n: u8) -> Option<Self> {
        if n <= 100 { Some(Self(n)) } else { None }
    }
}
```

## Parsing at Boundaries

```rust
// Parse at the system boundary (API, CLI, config file)
fn handle_request(raw: RawRequest) -> Result<Response, Error> {
    // Parse ALL inputs upfront
    let email = Email::parse(&raw.email)?;
    let age = Age::parse(raw.age)?;
    let username = Username::parse(&raw.username)?;
    
    // Now work with validated types
    process_user(email, age, username)
}

fn process_user(email: Email, age: Age, username: Username) {
    // All inputs guaranteed valid - no checks needed
}
```

## Evidence from sqlx

```rust
// sqlx parses SQL at compile time, ensuring query validity
// https://github.com/launchbadge/sqlx/blob/master/src/macros/mod.rs

// The query! macro parses and validates SQL
let user = sqlx::query!("SELECT * FROM users WHERE id = ?", id)
    .fetch_one(&pool)
    .await?;

// If SQL is invalid, compilation fails - invalid state unrepresentable
```

## Combining with Display

```rust
use std::fmt;

pub struct Email(String);

impl Email {
    pub fn parse(s: &str) -> Result<Self, EmailError> { ... }
}

// Implement Display for easy printing
impl fmt::Display for Email {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

// Implement AsRef for easy borrowing
impl AsRef<str> for Email {
    fn as_ref(&self) -> &str {
        &self.0
    }
}
```

## nutype: 2026 Gold Standard

The `nutype` crate (v0.7.0, `greyblake/nutype`) is the modern implementation of "parse, don't validate". It generates validated newtypes — including sanitization, validation, error types, `FromStr`, `Display`, `AsRef`, `Deref`, `Into`, and serde support — from a single attribute macro.

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, len_char_max = 100, regex = "^[^@]+@[^@]+$"),
    derive(Debug, Clone, Display, AsRef, Deref, FromStr, Into, Serialize, Deserialize)
)]
pub struct Email(String);

// Parsing at the boundary — the only place validation happens
fn handle_request(raw: RawRequest) -> Result<Response, Error> {
    let email = Email::new(raw.email)?;          // parse once
    let port = Port::new(raw.port)?;             // parse once
    process(email, port)                          // guaranteed valid
}

fn process(email: Email, port: Port) {
    // No validation needed — type system guarantees validity
    send_to(email, port);
}
```

### Anti-pattern: Validating at Every Boundary

```rust
// ❌ Validate everywhere — error-prone, wasteful, easy to forget
fn fn_a(email: &str) {
    if !valid_email(email) { return Err(...); }
    fn_b(email);
}
fn fn_b(email: &str) {
    if !valid_email(email) { return Err(...); }  // Repeat!
    fn_c(email);
}

// ✅ Parse once at the boundary, use the type everywhere
fn fn_a(email: Email) {
    fn_b(&email);  // Guaranteed valid
}
fn fn_b(email: &Email) {
    fn_c(email.as_ref());  // No checks needed
}
```

See [api-nutype-validated](./api-nutype-validated.md) for the full reference.

## See Also

- [api-nutype-validated](./api-nutype-validated.md) - nutype crate for validated newtypes
- [api-newtype-safety](./api-newtype-safety.md) - Use newtypes for type safety
- [type-newtype-validated](./type-newtype-validated.md) - Newtypes for validated data
- [api-typestate](./api-typestate.md) - Compile-time state machines
