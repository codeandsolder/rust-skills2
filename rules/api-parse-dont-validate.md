# api-parse-dont-validate

> Parse weakly typed input into invariant-bearing domain types at system boundaries instead of repeatedly validating primitives downstream

## Why It Matters

A validation function that returns only `bool` or `Result<(), E>` often leaves the program holding the same weak type it started with. Downstream code must then trust convention, repeat the check, or accept an invalid state in its type signature.

A parsing boundary returns a stronger type. If that type keeps construction closed and exposes only invariant-preserving operations, successful construction becomes evidence that the invariant holds.

This pattern is useful for configuration, HTTP/CLI input, identifiers, addresses, units, bounded numbers, and protocol states. It does not mean every local boolean condition deserves a wrapper type.

## Bad: Validate, Then Keep Passing the Primitive

<!-- rust-check: compile -->
```rust
fn valid_port(port: u16) -> bool {
    port != 0
}

fn open_connection(port: u16) {
    // The signature cannot express that callers were supposed to validate.
    assert!(valid_port(port));
    println!("connecting to {port}");
}

fn main() {
    let port = 443;
    if valid_port(port) {
        open_connection(port);
    }
}
```

## Good: Parse Into a Stronger Type

<!-- rust-check: compile -->
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Port(u16);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct InvalidPort;

impl Port {
    fn parse(value: u16) -> Result<Self, InvalidPort> {
        if value == 0 {
            Err(InvalidPort)
        } else {
            Ok(Self(value))
        }
    }

    fn get(self) -> u16 {
        self.0
    }
}

fn open_connection(port: Port) {
    println!("connecting to {}", port.get());
}

fn main() {
    open_connection(Port::parse(443).unwrap());
    assert!(Port::parse(0).is_err());
}
```

Code accepting `Port` no longer needs another `port != 0` check.

## Normalization Is Part of Parsing Semantics

A parser may normalize input when the domain contract calls for it. Do not silently normalize properties that are semantically meaningful.

<!-- rust-check: compile -->
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct Username(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct InvalidUsername;

impl Username {
    fn parse(raw: &str) -> Result<Self, InvalidUsername> {
        let value = raw.trim().to_ascii_lowercase();
        let valid = value.len() >= 3
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_');

        valid.then_some(Self(value)).ok_or(InvalidUsername)
    }

    fn as_str(&self) -> &str {
        &self.0
    }
}

fn main() {
    let username = Username::parse("  Alice_42 ").unwrap();
    assert_eq!(username.as_str(), "alice_42");
}
```

## Parse at the Boundary

Convert raw transport/input representations before entering domain logic. The boundary can also translate domain parse failures into the application's error type.

<!-- rust-check: compile -->
```rust
#[derive(Debug)]
struct RawRequest {
    email: String,
    age: String,
    username: String,
}

#[derive(Debug)]
struct Email(String);

#[derive(Debug)]
struct Age(u8);

#[derive(Debug)]
struct Username(String);

#[derive(Debug, PartialEq, Eq)]
struct Response {
    accepted: bool,
}

#[derive(Debug, PartialEq, Eq)]
enum Error {
    InvalidEmail,
    InvalidAge,
    InvalidUsername,
}

impl Email {
    fn parse(raw: &str) -> Result<Self, Error> {
        raw.split_once('@')
            .filter(|(local, domain)| !local.is_empty() && !domain.is_empty())
            .map(|_| Self(raw.to_owned()))
            .ok_or(Error::InvalidEmail)
    }
}

impl Age {
    fn parse(raw: &str) -> Result<Self, Error> {
        let value: u8 = raw.parse().map_err(|_| Error::InvalidAge)?;
        (value >= 18)
            .then_some(Self(value))
            .ok_or(Error::InvalidAge)
    }
}

impl Username {
    fn parse(raw: &str) -> Result<Self, Error> {
        (!raw.trim().is_empty())
            .then(|| Self(raw.trim().to_owned()))
            .ok_or(Error::InvalidUsername)
    }
}

fn handle_request(raw: RawRequest) -> Result<Response, Error> {
    let email = Email::parse(&raw.email)?;
    let age = Age::parse(&raw.age)?;
    let username = Username::parse(&raw.username)?;
    process_user(email, age, username)
}

fn process_user(email: Email, age: Age, username: Username) -> Result<Response, Error> {
    // Domain code receives already-parsed values. Reading the fields here only
    // prevents this compact example from leaving them entirely unused.
    let _domain_state = (email.0.len(), age.0, username.0.len());
    Ok(Response { accepted: true })
}

fn main() {
    let response = handle_request(RawRequest {
        email: "alice@example.com".to_owned(),
        age: "30".to_owned(),
        username: "alice".to_owned(),
    })
    .unwrap();

    assert_eq!(response, Response { accepted: true });
}
```

Do not immediately unwrap the domain type back into a primitive and pass that primitive everywhere; doing so discards most of the benefit.

## Construction Must Actually Be Closed

Private representation matters. Safe callers should not be able to bypass the checked constructor through public fields, unchecked mutable access, deserialization hooks, or alternate constructors.

<!-- rust-check: compile_fail; reason=private field prevents bypassing the checked constructor -->
```rust
mod domain {
    pub struct Percentage(u8);

    impl Percentage {
        pub fn parse(value: u8) -> Option<Self> {
            (value <= 100).then_some(Self(value))
        }
    }
}

fn main() {
    let _invalid = domain::Percentage(200);
}
```

`unsafe` or explicitly unchecked construction is a different contract; document and contain it accordingly.

## Rich Parse Errors

Parsing is a natural place to explain why input failed:

<!-- rust-check: compile -->
```rust
#[derive(Debug, PartialEq, Eq)]
struct NonEmpty(String);

#[derive(Debug, PartialEq, Eq)]
enum NonEmptyError {
    Empty,
}

impl NonEmpty {
    fn parse(raw: impl Into<String>) -> Result<Self, NonEmptyError> {
        let value = raw.into();
        if value.is_empty() {
            Err(NonEmptyError::Empty)
        } else {
            Ok(Self(value))
        }
    }
}

fn main() {
    assert_eq!(NonEmpty::parse(""), Err(NonEmptyError::Empty));
}
```

At an HTTP/CLI/configuration boundary, map these errors to the protocol's user-facing diagnostic while keeping internal APIs typed in terms of the strong value.

## Standard Conversion Traits

Use conventional fallible conversion traits when they fit the representation boundary:

<!-- rust-check: compile -->
```rust
use std::str::FromStr;

#[derive(Debug, PartialEq, Eq)]
struct Positive(u32);

#[derive(Debug, PartialEq, Eq)]
struct NotPositive;

impl TryFrom<u32> for Positive {
    type Error = NotPositive;

    fn try_from(value: u32) -> Result<Self, Self::Error> {
        if value > 0 {
            Ok(Self(value))
        } else {
            Err(NotPositive)
        }
    }
}

impl FromStr for Positive {
    type Err = String;

    fn from_str(raw: &str) -> Result<Self, Self::Err> {
        let value: u32 = raw.parse().map_err(|_| "not an integer".to_owned())?;
        Positive::try_from(value).map_err(|_| "must be positive".to_owned())
    }
}

fn main() {
    assert_eq!("42".parse::<Positive>().unwrap(), Positive(42));
    assert!("0".parse::<Positive>().is_err());
}
```

Use `From` for infallible conversions; use `TryFrom`, `FromStr`, or an explicit parse constructor when rejection is possible.

## Do Not Over-Parse Ephemeral Checks

<!-- rust-check: compile -->
```rust
fn display_if_nonempty(message: &str) {
    if !message.is_empty() {
        println!("{message}");
    }
}

fn main() {
    display_if_nonempty("hello");
}
```

A dedicated `NonEmptyDisplayMessage` type for this one local branch would add ceremony without carrying a durable invariant through an API.

## Decision Guide

| Situation | Typical approach |
|---|---|
| Raw input enters domain code | Parse into a domain type |
| Several functions rely on one invariant | Strong type usually pays off |
| Invalid representation must not be safely constructible | Private representation + checked construction |
| Conventional text/representation conversion | `FromStr` / `TryFrom` |
| One local conditional | Plain validation may be clearer |

## See Also

- [api-nutype-validated](./api-nutype-validated.md) — generated validated newtypes
- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-newtype-validated](./type-newtype-validated.md) — manual validated newtypes
- [api-typestate](./api-typestate.md) — state-machine invariants

## Reference

- [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
