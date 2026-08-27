# api-newtype-safety

> Use newtypes when identical representation hides meaning the compiler should distinguish

## Why It Matters

Raw primitives such as `u64` or `String` carry little domain meaning. If two values share the same representation but are not interchangeable—user IDs and group IDs, meters and seconds, validated and unvalidated strings—a newtype lets the compiler enforce that distinction with no runtime tagging requirement.

Use newtypes for meaningful invariants or confusion risks, not merely to wrap every primitive.

## Bad

```rust
#[derive(Debug)]
struct User {
    id: u64,
    group_id: u64,
    created_at_unix: u64,
}

fn membership_key(user_id: u64, group_id: u64) -> (u64, u64) {
    (user_id, group_id)
}

let user = User {
    id: 100,
    group_id: 5,
    created_at_unix: 1_234_567_890,
};

// Swapping values or passing a timestamp still type-checks.
let _swapped = membership_key(user.group_id, user.id);
let _nonsense = membership_key(user.created_at_unix, user.group_id);
```

## Good

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct UserId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct GroupId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Timestamp(u64);

#[derive(Debug)]
struct User {
    id: UserId,
    group_id: GroupId,
    created_at: Timestamp,
}

fn membership_key(user_id: UserId, group_id: GroupId) -> (UserId, GroupId) {
    (user_id, group_id)
}

let user = User {
    id: UserId(100),
    group_id: GroupId(5),
    created_at: Timestamp(1_234_567_890),
};

let key = membership_key(user.id, user.group_id);
assert_eq!(key, (UserId(100), GroupId(5)));
let _created_at = user.created_at;
```

A call such as `membership_key(user.group_id, user.id)` now fails to compile because `GroupId` is not `UserId`. The same applies to accidentally passing `Timestamp` as an ID.

## Derive the Traits the Semantics Support

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
struct OrderId(u64);

impl std::fmt::Display for OrderId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ORD-{:08}", self.0)
    }
}

assert_eq!(OrderId(42).to_string(), "ORD-00000042");
```

Do not derive traits merely because the wrapped field supports them. For example, ordering may be meaningless for some identifiers even though `u64: Ord`.

## Validated Newtypes

A private field plus a validating constructor can make invalid states unconstructible through the public API:

```rust
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

    fn as_str(&self) -> &str {
        &self.0
    }
}

let email = Email::parse("user@example.com").unwrap();
assert_eq!(email.as_str(), "user@example.com");
```

The validation here is intentionally minimal; real domain types should encode the actual invariant required by the application.

## Representation Is a Separate Decision

A single-field Rust newtype is often optimized exactly like its field, but source-level size equality is not itself a stable ABI/layout promise. Add `#[repr(transparent)]` only when the wrapper intentionally needs the wrapped field's layout/ABI contract, such as some FFI interfaces.

```rust
use std::mem::size_of;

struct Miles(f64);
struct Kilometers(f64);

assert_eq!(size_of::<Miles>(), size_of::<f64>());
assert_eq!(size_of::<Kilometers>(), size_of::<f64>());
```

Do not infer from this assertion that arbitrary transmutation or FFI interchange is safe; see the representation rule for those requirements.

## Serialization

When serialization should use the wrapped representation, serde can support transparent newtypes. Keep optional serialization dependencies feature-gated in general-purpose libraries.

<!-- rust-check: compile -->
```rust
#[derive(serde::Serialize, serde::Deserialize)]
#[serde(transparent)]
struct ProductId(u64);
```

## When Newtypes Help Most

- identifiers that are easy to swap,
- physical units or coordinate spaces,
- validated/sanitized values,
- secrets vs ordinary strings/bytes,
- values with different domain semantics but identical storage.

They are usually overkill when the wrapper has no useful semantic distinction and is only used once locally.

## See Also

- [api-nutype-validated](./api-nutype-validated.md) - Macro-generated validated newtypes
- [type-newtype-ids](./type-newtype-ids.md) - Newtype pattern for IDs
- [type-repr-transparent](./type-repr-transparent.md) - Explicit layout/ABI contract
- [api-parse-dont-validate](./api-parse-dont-validate.md) - Parse into validated types
