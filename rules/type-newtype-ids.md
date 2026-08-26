# type-newtype-ids

> Wrap IDs in newtypes

**Rule**: `type-newtype-ids`

## Why It Matters

Using raw integers for IDs is error-prone. It's easy to accidentally pass a `user_id` where a `post_id` is expected. Newtypes make these mix-ups compile-time errors instead of runtime bugs.

## Bad

```rust
fn get_user_posts(user_id: u64, post_id: u64) -> Vec<Post> {
    // Which is which? Easy to swap by accident
}

// Oops! Arguments swapped — compiles fine, wrong at runtime
let posts = get_user_posts(post_id, user_id);

// Even worse with multiple IDs
fn transfer(from: u64, to: u64, amount: u64) {
    // from/to can easily be swapped
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct PostId(pub u64);

fn get_user_posts(user_id: UserId, post_id: PostId) -> Vec<Post> {
    // Types are distinct
}

// This won't compile — types don't match
// let posts = get_user_posts(post_id, user_id);  // ERROR!

// Correct usage
let posts = get_user_posts(UserId(1), PostId(42));
```

## Reduce Boilerplate with `derive_more`

`derive_more` eliminates the manual trait implementations for newtypes:

```rust
use derive_more::{AsRef, Deref, Display, From};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, From, AsRef, Deref, Display)]
pub struct UserId(u64);

// From<u64> for UserId, AsRef<u64>, Deref<Target = u64>, Display
// all generated automatically.
let id = UserId::from(42u64);
println!("{id}");              // Display: "42"
let raw: u64 = *id;            // Deref
let r: &u64 = id.as_ref();     // AsRef
```

## `#[repr(transparent)]` + `NonZero<uN>` Niche Optimization

For IDs that must never be zero, combine `#[repr(transparent)]` with `NonZero<uN>` for a zero-cost `Option`:

```rust
use core::num::NonZero;
use derive_more::{Display, From};

#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display)]
pub struct UserId(NonZero<u64>);

impl UserId {
    pub fn new(raw: u64) -> Option<Self> {
        Some(Self(NonZero::new(raw)?))
    }

    pub fn get(self) -> u64 {
        self.0.get()
    }
}

// Option<UserId> is 8 bytes — same as u64
assert_eq!(std::mem::size_of::<Option<UserId>>(), 8);
```

## Validate with `nutype`

For IDs with validation rules (non-empty, specific format), use `nutype` for a validated newtype with automatic sanitization:

```rust
use nutype::nutype;
use core::num::NonZero;

#[nutype(
    validate(greater = 0),
    derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display, AsRef, Deref),
    serde(Serialize, Deserialize),
)]
pub struct UserId(u64);

// Guaranteed non-zero, with Display, AsRef, Deref, serde
```

## `From<T>` for `LazyCell`/`LazyLock` (Rust 1.96+)

Starting with Rust 1.96, `LazyCell` and `LazyLock` implement `From<T>`, making it ergonomic to initialize lazy ID types:

```rust
use std::cell::LazyCell;

// Before Rust 1.96: manual LazyCell::new(|| ...)
lazy_static! {
    static ref GUEST_ID: UserId = UserId::new(0).unwrap();
}

// After Rust 1.96: From<T> for LazyCell/LazyLock
let guest_id = LazyCell::from(UserId::new(0).unwrap());
```

## Derive Common Traits (Manual)

```rust
#[derive(
    Debug,      // For printing
    Clone,      // For copying
    Copy,       // For implicit copies (if small)
    PartialEq,  // For == comparison
    Eq,         // For HashMap keys
    Hash,       // For HashMap keys
    PartialOrd, // For sorting (optional)
    Ord,        // For BTreeMap keys (optional)
)]
pub struct UserId(pub u64);
```

## Add Useful Methods

```rust
pub struct UserId(u64);

impl UserId {
    pub const fn new(id: u64) -> Self { Self(id) }
    pub const fn get(self) -> u64 { self.0 }

    // For database queries
    pub fn as_i64(self) -> i64 { self.0 as i64 }
}

impl From<u64> for UserId {
    fn from(id: u64) -> Self { Self(id) }
}

impl std::fmt::Display for UserId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "user:{}", self.0)
    }
}
```

## With Serde

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]  // Serializes as just the inner value
pub struct UserId(pub u64);

// JSON: {"user_id": 123} not {"user_id": {"0": 123}}
```

## String IDs (UUIDs, etc.)

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SessionId(String);

impl SessionId {
    pub fn new() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }

    pub fn parse(s: &str) -> Result<Self, ParseError> {
        uuid::Uuid::parse_str(s)?;
        Ok(Self(s.to_string()))
    }

    pub fn as_str(&self) -> &str { &self.0 }
}
```

## Multiple Related IDs

```rust
// Macro for consistent ID types
macro_rules! define_id {
    ($name:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub struct $name(pub u64);

        impl $name {
            pub const fn new(id: u64) -> Self { Self(id) }
            pub const fn get(self) -> u64 { self.0 }
        }

        impl From<u64> for $name {
            fn from(id: u64) -> Self { Self(id) }
        }
    };
}

define_id!(UserId);
define_id!(PostId);
define_id!(CommentId);
define_id!(TeamId);
```

## See Also

- [api-newtype-safety](./api-newtype-safety.md) — Newtypes for type safety
- [type-newtype-validated](./type-newtype-validated.md) — Newtypes for validated data
- [type-nutype-validated](./type-nutype-validated.md) — `nutype` for validated newtypes
- [type-derive-more-boilerplate](./type-derive-more-boilerplate.md) — `derive_more` for boilerplate reduction
- [type-repr-transparent](./type-repr-transparent.md) — Layout guarantees for newtypes
- [type-nonzero-intrinsics](./type-nonzero-intrinsics.md) — `NonZero<uN>` niche optimization
- [api-parse-dont-validate](./api-parse-dont-validate.md) — Parse at boundaries
