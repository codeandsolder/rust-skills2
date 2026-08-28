# proj-mod-by-feature

> Prefer domain/feature-oriented modules when they keep code that changes together in one place

## Why It Matters

A module tree should make the codebase easier to navigate and preserve useful boundaries. In applications where each domain feature has a model, storage code, business logic, and handlers, a purely layer-oriented tree can scatter one change across many distant directories.

Feature-oriented modules are a useful default in that situation, not a universal law. Cross-cutting infrastructure, small projects, reusable libraries, and architectures with strong layer boundaries may be clearer with another shape.

## Layer-Only Layout Can Scatter a Feature

```text
src/
├── controllers/
│   ├── user.rs
│   ├── order.rs
│   └── product.rs
├── models/
│   ├── user.rs
│   ├── order.rs
│   └── product.rs
├── services/
│   ├── user.rs
│   ├── order.rs
│   └── product.rs
└── repositories/
    ├── user.rs
    ├── order.rs
    └── product.rs
```

If most changes are feature-local, this layout makes each feature span several directories.

## Feature-Oriented Alternative

```text
src/
├── user/
│   ├── mod.rs
│   ├── model.rs
│   ├── repository.rs
│   ├── service.rs
│   └── handler.rs
├── order/
│   ├── mod.rs
│   ├── model.rs
│   ├── repository.rs
│   ├── service.rs
│   └── handler.rs
├── product/
│   ├── mod.rs
│   ├── model.rs
│   ├── repository.rs
│   └── handler.rs
└── lib.rs
```

The useful property is cohesion: code that usually changes together is near each other.

## Module Boundary Example

```rust
mod user {
    mod model {
        #[derive(Debug)]
        pub struct User {
            pub id: u64,
        }

        #[derive(Debug, Clone, Copy)]
        pub struct UserId(pub u64);

        pub struct CreateUserRequest {
            pub id: u64,
        }
    }

    mod repository {
        use super::model::User;

        pub(crate) fn load(id: u64) -> User {
            User { id }
        }
    }

    mod service {
        use super::{model::User, repository};

        pub struct UserService;

        impl UserService {
            pub fn load(&self, id: u64) -> User {
                repository::load(id)
            }
        }
    }

    mod handler {
        pub fn router() -> &'static str {
            "/users"
        }
    }

    pub use self::handler::router;
    pub use self::model::{CreateUserRequest, User, UserId};
    pub(crate) use self::service::UserService;
}

fn main() {
    let service = user::UserService;
    let user = service.load(7);
    assert_eq!(user.id, 7);
    assert_eq!(user::router(), "/users");
}
```

Private submodules let the feature expose a small public surface while its internal layers remain reorganizable.

## Shared and Cross-Cutting Code

Do not force infrastructure into arbitrary feature folders:

```text
src/
├── user/
├── order/
├── database.rs
├── telemetry.rs
├── config.rs
└── lib.rs
```

A `shared/` or `common/` directory can be useful, but watch for it becoming a miscellaneous dumping ground. Prefer names that describe a real capability when one emerges.

## When to Flatten

Small modules do not need five files merely to satisfy a pattern:

```text
src/
├── user.rs
├── config.rs
└── lib.rs
```

Split a feature when the extra boundary improves navigation, ownership, testing, or reuse—not because every conceptual layer deserves a file.

## Decision Guide

| Dominant change pattern | Often clearer |
|---|---|
| Features change mostly independently | Feature/domain modules |
| Infrastructure reused across many features | Cross-cutting modules |
| Small crate with few items | Flat module tree |
| Public reusable library organized around concepts/types | API-oriented modules |
| Strong architectural layer boundaries are themselves important | Layered or hybrid layout |

## See Also

- [proj-flat-small](./proj-flat-small.md) - Keep small projects flat
- [proj-pub-use-reexport](./proj-pub-use-reexport.md) - Curate module public APIs
- [proj-lib-main-split](./proj-lib-main-split.md) - Library/binary separation
