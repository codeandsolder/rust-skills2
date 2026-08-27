# test-mock-traits

> Put meaningful external dependencies behind replaceable boundaries when that improves testing

## Why It Matters

A service that directly constructs and calls a database, clock, HTTP client, filesystem wrapper, or other external dependency is harder to exercise deterministically. A trait can define the small capability the service actually needs, allowing production and test implementations to be injected separately.

Do not introduce a trait solely because “tests need mocks.” Prefer the narrowest useful seam: a plain function parameter, generic closure, concrete in-memory implementation, or trait depending on the shape and reuse of the dependency.

## Bad

```rust
struct UserService;

impl UserService {
    fn display_name(&self, id: u64) -> String {
        // Imagine this constructs a real database connection internally.
        real_database_lookup(id).unwrap_or_else(|| "missing".to_string())
    }
}

fn real_database_lookup(_id: u64) -> Option<String> {
    None
}

fn main() {}
```

The behavior under “found”, “missing”, or dependency failure is coupled to the real dependency.

## Good

```rust
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq, Eq)]
struct User {
    id: u64,
    name: String,
}

trait UserRepository {
    fn find_by_id(&self, id: u64) -> Option<User>;
}

struct UserService<R> {
    repo: R,
}

impl<R: UserRepository> UserService<R> {
    fn get_user(&self, id: u64) -> Result<User, ServiceError> {
        self.repo.find_by_id(id).ok_or(ServiceError::NotFound)
    }
}

#[derive(Debug, PartialEq, Eq)]
enum ServiceError {
    NotFound,
}

#[derive(Default)]
struct FakeRepository {
    users: HashMap<u64, User>,
}

impl UserRepository for FakeRepository {
    fn find_by_id(&self, id: u64) -> Option<User> {
        self.users.get(&id).cloned()
    }
}

fn main() {
    let mut repo = FakeRepository::default();
    repo.users.insert(1, User { id: 1, name: "Alice".into() });

    let service = UserService { repo };
    assert_eq!(service.get_user(1).unwrap().name, "Alice");
    assert_eq!(service.get_user(99), Err(ServiceError::NotFound));
}
```

A small fake is often clearer than a programmable mocking framework when the test cares about state/results rather than exact interaction ordering.

## Native Async Trait Methods

Native `async fn` in traits stabilized in Rust 1.75; it is not an Edition 2024 feature. It works well with static/generic dispatch:

<!-- rust-check: compile -->
```rust
#[derive(Clone)]
struct User;

#[derive(Debug)]
struct RepoError;

trait AsyncRepository {
    async fn find_by_id(&self, id: u64) -> Result<Option<User>, RepoError>;
}

struct FakeRepository;

impl AsyncRepository for FakeRepository {
    async fn find_by_id(&self, _id: u64) -> Result<Option<User>, RepoError> {
        Ok(Some(User))
    }
}

async fn lookup<R: AsyncRepository>(repo: &R, id: u64) -> Result<Option<User>, RepoError> {
    repo.find_by_id(id).await
}

fn main() {}
```

A trait containing native `async fn` is not dyn-compatible in the form above, because the method's hidden future type cannot be dispatched through a vtable. Therefore `Box<dyn AsyncRepository>` is **not** a drop-in alternative to generic dispatch.

## Dynamic Dispatch for Async Boundaries

If dynamic dispatch is required, expose an object-safe method whose return type is itself erased, or use a well-understood helper crate that performs equivalent boxing.

<!-- rust-check: compile -->
```rust
use std::{future::Future, pin::Pin};

type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

#[derive(Clone)]
struct User;

#[derive(Debug)]
struct RepoError;

trait DynRepository: Send + Sync {
    fn find_by_id(&self, id: u64) -> BoxFuture<'_, Result<Option<User>, RepoError>>;
}

struct FakeRepository;

impl DynRepository for FakeRepository {
    fn find_by_id(&self, _id: u64) -> BoxFuture<'_, Result<Option<User>, RepoError>> {
        Box::pin(async { Ok(Some(User)) })
    }
}

struct UserService {
    repo: Box<dyn DynRepository>,
}

fn main() {
    let _service = UserService { repo: Box::new(FakeRepository) };
}
```

This buys dyn dispatch at the cost of type erasure and, in this common representation, a boxed future allocation. Choose it because the architecture needs heterogeneous runtime implementations, not merely to avoid generic syntax.

## Mocks, Fakes, and Interaction Tests

Use a hand-written fake when stateful behavior is simple. A mocking crate such as `mockall` is useful when tests need to assert calls, arguments, ordering, or configured failures. HTTP-level tools such as `wiremock` test a different boundary: the serialized protocol behavior rather than a Rust trait.

Keep unit tests and integration tests complementary. Replacing every external system with a mock can make tests fast while missing schema, protocol, configuration, or deployment failures that only an integration test can catch.

## See Also

- [api-sealed-trait](./api-sealed-trait.md) - Trait design
- [test-mockall-mocking](./test-mockall-mocking.md) - Mockall details
- [test-proptest-properties](./test-proptest-properties.md) - Property-based testing
- [proj-lib-main-split](./proj-lib-main-split.md) - Testable architecture
