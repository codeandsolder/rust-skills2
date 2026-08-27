# api-parse-dont-validate

> Parse weakly typed input into invariant-bearing domain types at system boundaries instead of repeatedly validating primitives downstream

## Why It Matters

Validation that leaves the program holding the same `String`, `u16`, or other primitive does not record that the check happened. Every downstream caller must either trust convention or repeat the check.

A parsing boundary returns a stronger type. If that type keeps its representation private and exposes only invariant-preserving operations, successful construction becomes evidence the invariant holds.

This pattern is useful for configuration, HTTP/CLI input, identifiers, addresses, units, bounded numbers, and protocol states. It does **not** mean every boolean check deserves a wrapper type; use it when the invariant matters across an API boundary or through a meaningful part of the program.

## Bad: Validate, Then Keep Passing the Primitive

```rust
fn valid_port(port: u16) -> bool {
    port != 0
}

fn open_connection(port: u16) {
    // Must trust callers or check again.
    assert!(valid_port(port));
    println!("connecting to {port}");
}

fn handle_input(port: u16) {
    if valid_port(port) {
        open_connection(port);
    }
}

fn main() {
    handle_input(443);
}
```

After `valid_port` returns true, the value is still merely a `u16`; nothing in `open_connection`'s signature records the guarantee.

## Good: Parse Into a Stronger Type

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
    // The invariant is encoded by the parameter type.
    println!("connecting to {}", port.get());
}

fn main() {
    let port = Port::parse(443).unwrap();
    open_connection(port);
    assert!(Port::parse(0).is_err());
}
```

The validation occurs at construction. Code that accepts `Port` no longer needs a second `port != 0` check.

## String Example: Normalize and Validate Once

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct Username(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct InvalidUsername;

impl Username {
    fn parse(raw: &str) -> Result<Self, InvalidUsername> {
        let value = raw.trim().to_lowercase();

        if value.len() >= 3
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_')
        {
            Ok(Self(value))
        } else {
            Err(InvalidUsername)
        }
    }

    fn as_str(&self) -> &str {
        &self.0
    }
}

fn greeting(username: &Username) -> String {
    format!("hello {}", username.as_str())
}

fn main() {
    let username = Username::parse("  Alice_42 ").unwrap();
    assert_eq!(greeting(&username), "hello alice_42");
}
```

Here normalization is part of parsing semantics. In another domain, changing case might be wrong and invalid input should instead be rejected. Parsing should implement the domain's actual contract, not silently “clean” data by default.

## Parse at the Boundary

Convert raw inputs when they enter the trusted/domain portion of the application:

<!-- rust-check: fragment; reason=application boundary example uses project-specific request, response, and error types -->
```rust
fn handle_request(raw: RawRequest) -> Result<Response, Error> {
    let email = Email::parse(&raw.email)?;
    let age = Age::parse(raw.age)?;
    let username = Username::parse(&raw.username)?;

    process_user(email, age, username)
}

fn process_user(
    email: Email,
    age: Age,
    username: Username,
) -> Result<Response, Error> {
    // Domain logic receives already-parsed values.
    todo!()
}
```

Do not immediately convert the strong type back to the raw primitive and then pass that everywhere; doing so discards most of the benefit.

## Construction Must Actually Be Closed

A “validated” type does not guarantee anything if safe callers can bypass validation:

<!-- rust-check: compile_fail; reason=demonstrates that a private field prevents bypassing the checked constructor -->
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
    // Private field prevents bypassing Percentage::parse from here.
    let _invalid = domain::Percentage(200);
}
```

Keep fields private and expose operations that preserve the invariant. Be equally careful with deserialization, mutable accessors, unchecked constructors, FFI, and other alternate construction paths.

## Parsing Can Return Rich Errors

The parsing function is a good place to explain *why* input was rejected:

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

At a user-facing boundary, map domain parsing errors into an HTTP response, CLI diagnostic, configuration error, etc. Internal APIs can keep accepting the strong type.

## `FromStr` and `TryFrom` Are Natural Boundary Traits

When textual or representation conversions are conventional, implement the standard fallible conversion traits so boundary code composes with the ecosystem:

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

Use `From` only for infallible conversions. A conversion that can reject input belongs in `TryFrom`, `FromStr`, or an explicit parse constructor.

## Using `nutype`

`nutype` 0.7 can generate the same kind of invariant-bearing API when the macro removes enough boilerplate to be worthwhile:

```rust
use nutype::nutype;

#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, len_char_max = 100),
    derive(Debug, Clone, PartialEq, Eq, Display, AsRef, FromStr, TryFrom),
)]
struct EmailLabel(String);

fn main() {
    // Validation means the constructor is `try_new` in nutype 0.7.
    let label = EmailLabel::try_new("  Alice  ").unwrap();
    assert_eq!(label.as_ref(), "alice");

    // FromStr performs the same sanitize/validate construction.
    assert!("   ".parse::<EmailLabel>().is_err());
}
```

Do not treat a particular macro as the principle itself. The invariant-bearing type is the important part; a hand-written newtype may be simpler, while `nutype` is attractive when sanitizers, validators, errors, conversions, or serde support would otherwise be repetitive.

For regex, serde, `const_fn`, exact generated error variants, and feature setup, use the dedicated current-version guidance in [api-nutype-validated](./api-nutype-validated.md).

## Do Not Over-Parse Ephemeral Checks

A strong type is less useful when the property is local and immediately consumed:

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

Creating `NonEmptyDisplayMessage` solely for this branch would add ceremony without carrying a durable invariant across an API boundary.

## Decision Guide

| Situation | Typical approach |
|---|---|
| Raw input enters domain code | Parse into a domain type |
| Several functions rely on the same invariant | Strong type usually pays off |
| Invalid representation must not be constructible safely | Private representation + checked constructors |
| Text/representation conversion is conventional | `FromStr` / `TryFrom` |
| Tiny invariant with small API | Hand-written newtype |
| Repetitive sanitizer/validator/trait boilerplate | Consider `nutype` |
| One local conditional check | Plain validation may be clearer |

## See Also

- [api-nutype-validated](./api-nutype-validated.md) — current `nutype` API details
- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-newtype-validated](./type-newtype-validated.md) — manual validated newtypes
- [type-nutype-validated](./type-nutype-validated.md) — validated type design with `nutype`
- [api-typestate](./api-typestate.md) — state-machine invariants in types

## References

- [Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [nutype documentation](https://docs.rs/nutype/latest/nutype/)
