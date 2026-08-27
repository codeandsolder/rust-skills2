# type-no-stringly

> Replace durable stringly-typed states and identifiers with enums or domain types, while keeping text parsing at system boundaries

**Rule**: `type-no-stringly`

## Why It Matters

A `String` can hold any spelling, so APIs that use strings for a closed set of states or for values with strong invariants push mistakes into runtime checks. Enums and newtypes make the accepted domain explicit, improve exhaustiveness checking, and give parsers a natural boundary.

Strings remain the correct representation for genuinely open-ended text. The goal is not “never use strings”; it is to stop using strings as an undocumented type system.

## Bad: Closed States as Strings

```rust
fn can_ship(status: &str) -> bool {
    match status {
        "paid" => true,
        "pending" | "cancelled" => false,
        _ => false,
    }
}

fn main() {
    assert!(!can_ship("Paid")); // typo/casing silently becomes another state
}
```

The function cannot distinguish “a valid non-shippable state” from “a spelling nobody intended.”

## Good: Enum for a Closed Set

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Status {
    Pending,
    Paid,
    Cancelled,
}

fn can_ship(status: Status) -> bool {
    match status {
        Status::Paid => true,
        Status::Pending | Status::Cancelled => false,
    }
}

fn main() {
    assert!(can_ship(Status::Paid));
    assert!(!can_ship(Status::Pending));
}
```

Adding a new variant now forces relevant exhaustive matches to be reconsidered by the compiler.

## Parse Text at the Boundary

```rust
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Priority {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsePriority;

impl FromStr for Priority {
    type Err = ParsePriority;

    fn from_str(raw: &str) -> Result<Self, Self::Err> {
        match raw {
            "low" => Ok(Self::Low),
            "medium" => Ok(Self::Medium),
            "high" => Ok(Self::High),
            _ => Err(ParsePriority),
        }
    }
}

fn main() {
    let priority: Priority = "high".parse().unwrap();
    assert_eq!(priority, Priority::High);
    assert!("urgent".parse::<Priority>().is_err());
}
```

The textual representation is still accepted where text enters the program, but the rest of the domain works with `Priority`.

## `derive_more::FromStr` for Simple Newtypes

For a one-field newtype whose inner type already implements `FromStr`, derive-more can forward parsing directly. The current derive does not need an old `#[from_str(forward)]` marker for the ordinary newtype case.

```rust
use derive_more::FromStr;

#[derive(Debug, Clone, PartialEq, Eq, FromStr)]
struct Username(String);

fn main() {
    let username: Username = "alice".parse().unwrap();
    assert_eq!(username.0, "alice");
}
```

This is appropriate when parsing the wrapper should have exactly the inner type's parsing semantics. It is **not validation**: wrapping `String` this way still accepts every string.

If the domain has an invariant, write a checked parser/newtype or use a validated-newtype helper instead of relying on a forwarding derive.

## Custom Parsing Errors With derive-more

When forwarding from an inner parser but exposing a domain-specific error type, use the current `error(...)` attribute form.

```rust
use derive_more::{From, FromStr};

#[derive(Debug, From)]
struct PortError(std::num::ParseIntError);

#[derive(Debug, PartialEq, Eq, FromStr)]
#[from_str(error(PortError))]
struct Port(u16);

fn main() {
    assert_eq!("443".parse::<Port>().unwrap(), Port(443));
    assert!("https".parse::<Port>().is_err());
}
```

That conversion only changes the parse error surface; it does not add range/domain validation beyond what the inner parser already performs.

## Validated Newtypes for Open Text With Invariants

An email address, username, slug, or protocol token may still be text while needing stronger construction semantics.

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct Username(String);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct InvalidUsername;

impl Username {
    fn parse(raw: &str) -> Result<Self, InvalidUsername> {
        let valid = !raw.is_empty()
            && raw.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
        valid.then(|| Self(raw.to_owned())).ok_or(InvalidUsername)
    }
}

fn main() {
    assert!(Username::parse("alice_42").is_ok());
    assert!(Username::parse("alice 42").is_err());
}
```

Here `String` is still the representation, but callers cannot construct the domain type from arbitrary text through the safe API.

## Typed Configuration Instead of Key/Value Strings

Prefer a structured configuration type when fields have distinct semantics:

```rust
use std::time::Duration;

#[derive(Debug, Clone, Copy)]
enum Mode {
    Fast,
    Safe,
}

#[derive(Debug)]
struct Config {
    timeout: Duration,
    retries: u32,
    mode: Mode,
}

fn main() {
    let config = Config {
        timeout: Duration::from_secs(5),
        retries: 3,
        mode: Mode::Safe,
    };
    assert_eq!(config.retries, 3);
    assert!(matches!(config.mode, Mode::Safe));
    assert_eq!(config.timeout.as_secs(), 5);
}
```

A generic `configure("timeout", "5")` interface loses field names, units, and accepted value sets in one step.

## Serde Can Keep the Wire Format Textual

Typed Rust APIs do not require changing an external JSON/YAML/TOML representation.

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum EventType {
    UserCreated,
    UserDeleted,
}

fn main() {
    let encoded = serde_json::to_string(&EventType::UserCreated).unwrap();
    assert_eq!(encoded, r#""user_created""#);
    let decoded: EventType = serde_json::from_str(&encoded).unwrap();
    assert_eq!(decoded, EventType::UserCreated);
}
```

The boundary can remain string-based while internal code gains type checking.

## When Strings Are Correct

Keep ordinary strings for:

- user-authored prose;
- labels and names without a useful closed/invariant-bearing domain;
- opaque external values that the program intentionally does not interpret;
- extensible/plugin identifiers where a closed enum would incorrectly reject future values.

Creating a newtype for every local string can add ceremony without preserving any meaningful invariant.

## See Also

- [anti-stringly-typed](./anti-stringly-typed.md) — stringly API anti-patterns
- [type-newtype-validated](./type-newtype-validated.md) — validated text/domain values
- [type-enum-states](./type-enum-states.md) — closed state sets
- [type-derive-more-boilerplate](./type-derive-more-boilerplate.md) — derive-more helpers

## References

- [`std::str::FromStr`](https://doc.rust-lang.org/std/str/trait.FromStr.html)
- [`derive_more::FromStr`](https://docs.rs/derive_more/latest/derive_more/derive.FromStr.html)
