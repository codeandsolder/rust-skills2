# anti-stringly-typed

> Don't use strings where enums or newtypes provide a meaningful domain type

## Why It Matters

Strings are appropriate for free-form text and external wire formats, but they are a poor internal representation for a closed set of states or a value with important invariants. Encoding those concepts as enums or newtypes lets the compiler reject swapped arguments and invalid states, centralizes validation, and makes APIs self-documenting.

Parse untrusted strings at boundaries, then use typed values internally.

## Bad

```rust
fn process_order(status: &str, priority: &str) -> bool {
    matches!((status, priority),
        ("pending" | "processing" | "completed" | "cancelled",
         "low" | "medium" | "high" | "critical"))
}

// These mistakes still type-check because both arguments are &str.
assert!(!process_order("complete", "high"));
assert!(!process_order("high", "pending"));
```

Runtime checks have to rediscover invariants that could instead be represented in the type system.

## Good

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OrderStatus {
    Pending,
    Processing,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Priority {
    Low,
    Medium,
    High,
    Critical,
}

fn process_order(status: OrderStatus, priority: Priority) -> &'static str {
    match (status, priority) {
        (OrderStatus::Cancelled, _) => "cancelled",
        (OrderStatus::Completed, _) => "complete",
        (_, Priority::Critical) => "expedite",
        _ => "normal",
    }
}

assert_eq!(
    process_order(OrderStatus::Completed, Priority::High),
    "complete"
);
```

A call such as `process_order(Priority::High, OrderStatus::Pending)` does not compile because the two concepts are different types.

## Validated Newtypes

Use a newtype when the set of values is open-ended but construction has invariants:

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct UserId(u64);

#[derive(Debug, Clone, PartialEq, Eq)]
struct Email(String);

#[derive(Debug, Clone, PartialEq, Eq)]
enum EmailError {
    MissingAtSign,
}

impl Email {
    fn parse(input: impl Into<String>) -> Result<Self, EmailError> {
        let input = input.into();
        if input.contains('@') {
            Ok(Self(input))
        } else {
            Err(EmailError::MissingAtSign)
        }
    }
}

struct User {
    id: UserId,
    email: Email,
}

let user = User {
    id: UserId(42),
    email: Email::parse("user@example.com").unwrap(),
};
assert_eq!(user.id, UserId(42));
```

Real email validation is more involved than checking for `@`; the example only demonstrates where validation belongs. Use a domain-appropriate parser for the actual invariant.

## Parsing Strings to Types

```rust
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OrderStatus {
    Pending,
    Processing,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParseStatusError(String);

impl FromStr for OrderStatus {
    type Err = ParseStatusError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "pending" => Ok(Self::Pending),
            "processing" => Ok(Self::Processing),
            "completed" => Ok(Self::Completed),
            "cancelled" | "canceled" => Ok(Self::Cancelled),
            other => Err(ParseStatusError(other.to_owned())),
        }
    }
}

fn handle_request(status: &str) -> Result<OrderStatus, ParseStatusError> {
    status.parse()
}

assert_eq!(handle_request("completed"), Ok(OrderStatus::Completed));
```

## With Serde

Serde can perform the boundary conversion directly:

<!-- rust-check: fragment; reason=requires serde derive dependency/features in the consuming crate -->
```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Status {
    Pending,
    InProgress,
    Completed,
}
```

This is usually preferable to carrying `serde_json::Value` or manually matched string fields deep into application logic.

## When Strings Are Fine

Keep `String`/`str` for genuinely unconstrained text, opaque user-provided data, or a boundary representation that is immediately parsed. Do not create a newtype merely to make every string nominally distinct; the extra type should encode useful semantics or prevent a realistic class of mistakes.

## See Also

- [api-newtype-safety](./api-newtype-safety.md) - Newtype pattern
- [api-parse-dont-validate](./api-parse-dont-validate.md) - Parse at boundaries
- [type-newtype-ids](./type-newtype-ids.md) - Type-safe IDs
