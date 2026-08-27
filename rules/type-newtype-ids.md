# type-newtype-ids

> Wrap semantically distinct IDs in distinct types, and encode additional invariants such as non-zero values at construction

**Rule**: `type-newtype-ids`

## Why It Matters

Raw integers do not distinguish a `UserId` from an `OrderId`. A newtype turns that distinction into a compile-time property while still allowing a compact representation.

Keep the wrapper's construction semantics aligned with the domain. If zero is invalid, encode that with `NonZero`; if parsing or validation is more involved, use a checked constructor or a validated-newtype helper such as `nutype`.

## Bad: Interchangeable Primitive IDs

```rust
fn load_membership(user_id: u64, team_id: u64) -> (u64, u64) {
    (user_id, team_id)
}

fn main() {
    let user_id = 7;
    let team_id = 42;

    // Compiles even though the arguments are reversed.
    let membership = load_membership(team_id, user_id);
    assert_eq!(membership, (42, 7));
}
```

## Good: Distinct ID Types

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TeamId(u64);

fn load_membership(user_id: UserId, team_id: TeamId) -> (UserId, TeamId) {
    (user_id, team_id)
}

fn main() {
    let user_id = UserId(7);
    let team_id = TeamId(42);

    let membership = load_membership(user_id, team_id);
    assert_eq!(membership, (user_id, team_id));

    // load_membership(team_id, user_id); // type mismatch
}
```

A public ID type usually benefits from a private field plus deliberate constructors/accessors so representation changes do not leak through every caller.

## Non-Zero IDs

When zero is not a valid identifier, make that invariant structural:

```rust
use core::num::NonZero;

#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(NonZero<u64>);

impl UserId {
    pub fn new(raw: u64) -> Option<Self> {
        NonZero::new(raw).map(Self)
    }

    pub fn get(self) -> u64 {
        self.0.get()
    }
}

fn main() {
    assert!(UserId::new(0).is_none());
    assert_eq!(UserId::new(42).unwrap().get(), 42);

    assert_eq!(
        core::mem::size_of::<Option<UserId>>(),
        core::mem::size_of::<u64>(),
    );
}
```

The `Option<NonZero<T>>` niche/layout guarantee is useful for optional handles without adding a separate discriminant.

## Validated IDs With `nutype` 0.7

For repeated validation/serialization boilerplate, `nutype` can generate a checked API. With validation present, the constructor is `try_new`, and serde traits belong in `derive(...)` when the crate's `serde` feature is enabled.

```rust
use nutype::nutype;

#[nutype(
    validate(greater = 0),
    derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display, Serialize, Deserialize),
)]
pub struct UserId(u64);

fn main() {
    let id = UserId::try_new(42).unwrap();
    assert!(UserId::try_new(0).is_err());
    assert_eq!(id.to_string(), "42");

    let json = serde_json::to_string(&id).unwrap();
    let decoded: UserId = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded, id);
}
```

Do not copy older `serde(...)` attribute syntax or call `new()` on a validated `nutype`; those are not the `nutype` 0.7 API taught by this repository.

## Transparent Serde for a Manual Newtype

If the serialized representation should be exactly the inner primitive, serde can make that explicit:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct UserId(u64);

fn main() {
    let id = UserId(123);
    assert_eq!(serde_json::to_string(&id).unwrap(), "123");
}
```

Serialization does not itself validate a manual newtype. If deserialization must enforce an invariant, route it through a checked conversion or custom `Deserialize` implementation.

## Generate Families of Simple IDs Deliberately

A tiny local macro can reduce repetition without erasing type distinctions:

```rust
macro_rules! define_id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub struct $name(u64);

        impl $name {
            pub const fn new(raw: u64) -> Self { Self(raw) }
            pub const fn get(self) -> u64 { self.0 }
        }
    };
}

define_id!(UserId);
define_id!(PostId);

fn main() {
    let user = UserId::new(1);
    let post = PostId::new(1);
    assert_eq!(user.get(), post.get());
    // user == post; // type mismatch
}
```

Prefer a small hand-written type when it has custom semantics; macro generation is most useful when many IDs intentionally share the same API.

## See Also

- [api-newtype-safety](./api-newtype-safety.md) — semantic newtypes
- [type-newtype-validated](./type-newtype-validated.md) — validation at construction
- [type-nutype-validated](./type-nutype-validated.md) — current `nutype` guidance
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — `NonZero` invariants and arithmetic
- [type-repr-transparent](./type-repr-transparent.md) — when to promise wrapped layout/ABI
