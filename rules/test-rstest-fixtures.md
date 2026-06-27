# test-rstest-fixtures

> Use `rstest` for parameterized tests, fixtures, and async test setup

## Why It Matters

Writing test fixtures and parameterized tests by hand leads to boilerplate duplication. `rstest` (48.8M+ downloads, v0.26.1) provides a declarative approach: `#[fixture]` for shared setup, `#[case]` for parameterized cases, `#[future]` for async fixtures, and named cases for descriptive test output. It integrates seamlessly with `#[tokio::test]`.

## Setup

```toml
# Cargo.toml
[dev-dependencies]
rstest = "0.26"
```

## Fixtures

```rust
use rstest::*;

#[fixture]
fn user_repo() -> MockUserRepo {
    let mut repo = MockUserRepo::new();
    repo.expect_find_by_id()
        .returning(|_| Some(User { id: 1, name: "Alice".into() }));
    repo
}

#[fixture]
fn service(user_repo: MockUserRepo) -> UserService<MockUserRepo> {
    UserService::new(user_repo)
}

// Fixtures are automatically injected by name
#[rstest]
fn test_get_user(service: UserService<MockUserRepo>) {
    let user = service.find_user(1).unwrap();
    assert_eq!(user.name, "Alice");
}
```

## Parameterized Tests

```rust
use rstest::*;

#[rstest]
#[case::empty_string("", true)]
#[case::whitespace("   ", true)]
#[case::valid_input("hello", false)]
fn test_is_blank(#[case] input: &str, #[case] expected: bool) {
    assert_eq!(input.trim().is_empty(), expected);
}

// Test output:
// test_is_blank::empty_string
// test_is_blank::whitespace
// test_is_blank::valid_input
```

## Async Fixtures

```rust
use rstest::*;

#[fixture]
async fn db_pool() -> PgPool {
    PgPool::connect("postgres://localhost/test").await.unwrap()
}

#[rstest]
#[tokio::test]
async fn test_query_users(db_pool: PgPool) {
    let users = query_users(&db_pool).await.unwrap();
    assert!(!users.is_empty());
}

// With explicit #[future] attribute
#[rstest]
#[future]
async fn test_with_future(#[future] db_pool: PgPool) {
    let pool = db_pool.await;
    // ...
}
```

## Named Cases with Values

```rust
use rstest::*;

#[rstest]
#[case::zero(0, false)]
#[case::one(1, true)]
#[case::boundary(i32::MAX, true)]
#[case::negative(-1, false)]
fn test_is_positive(#[case] input: i32, #[case] expected: bool) {
    assert_eq!(input > 0, expected);
}
```

## Matrix Tests (All Combinations)

```rust
use rstest::*;

#[rstest]
#[case(1)]
#[case(2)]
fn test_single_param(#[case] a: i32) { /* ... */ }

// #[matrix] attribute generates cartesian product
#[rstest]
fn test_matrix(
    #[values(1, 2, 3)] a: i32,
    #[values("x", "y")] b: &str,
) {
    // Runs 6 times: (1,"x"), (1,"y"), (2,"x"), (2,"y"), (3,"x"), (3,"y")
}
```

## Combining with Other Attributes

```rust
use rstest::*;

#[rstest]
#[case::simple("valid", true)]
#[tokio::test]
async fn test_async_param(#[case] input: &str, #[case] expected: bool) {
    let result = validate(input).await;
    assert_eq!(result, expected);
}

// With serial_test for shared resource access
#[rstest]
#[case::db_write("data")]
#[serial_test::serial]
fn test_serialized(#[case] input: &str) {
    // Only one test at a time
}
```

## Fixture Composition

```rust
use rstest::*;

#[fixture]
fn config() -> Config {
    Config { timeout: 30, retries: 3 }
}

#[fixture]
fn client(config: Config) -> Client {
    Client::new(config)
}

#[fixture]
fn auth_client(client: Client) -> AuthClient {
    AuthClient::new(client, "test-token")
}

// Inject the composed fixture
#[rstest]
fn test_authenticated_request(auth_client: AuthClient) {
    let response = auth_client.get("/api/data").unwrap();
    assert!(response.is_ok());
}
```

## See Also

- [rstest crate](https://crates.io/crates/rstest) — v0.26.1
- [rstest GitHub](https://github.com/la10736/rstest)
- [test-fixture-raii](./test-fixture-raii.md) — RAII cleanup patterns
- [test-arrange-act-assert](./test-arrange-act-assert.md) — Test structure with rstest
- [test-descriptive-names](./test-descriptive-names.md) — Named test cases
- [test-tokio-async](./test-tokio-async.md) — Async test runtime
