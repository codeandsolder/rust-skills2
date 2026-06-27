# test-mock-traits

> Use traits for dependencies to enable mocking in tests

## Why It Matters

Concrete dependencies make testing hard—you can't easily test error paths, timeouts, or edge cases without real external systems. Extracting dependencies behind traits lets you inject test doubles (mocks, fakes, stubs), enabling isolated unit tests that run fast and cover edge cases.

## Bad

```rust
struct UserService {
    db: PostgresConnection,  // Concrete type - hard to test
}

impl UserService {
    async fn get_user(&self, id: u64) -> Result<User, Error> {
        // Directly calls Postgres - needs real database to test
        self.db.query("SELECT * FROM users WHERE id = $1", &[&id]).await
    }
}

// Test requires real Postgres instance
#[tokio::test]
async fn test_get_user() {
    let db = PostgresConnection::connect("postgres://...").await?;
    let service = UserService { db };
    // Slow, flaky, can't test error paths
}
```

## Good

```rust
// Define trait for dependency
// Edition 2024: native async fn in traits — no #[async_trait] needed!
trait UserRepository: Send + Sync {
    async fn find_by_id(&self, id: u64) -> Result<Option<User>, DbError>;
    async fn save(&self, user: &User) -> Result<(), DbError>;
}

// Production implementation
struct PostgresUserRepo {
    pool: PgPool,
}

impl UserRepository for PostgresUserRepo {
    async fn find_by_id(&self, id: u64) -> Result<Option<User>, DbError> {
        sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(id)
            .fetch_optional(&self.pool)
            .await
    }
    // ...
}

// Service depends on trait, not concrete type
struct UserService<R: UserRepository> {
    repo: R,
}

impl<R: UserRepository> UserService<R> {
    async fn get_user(&self, id: u64) -> Result<User, Error> {
        self.repo.find_by_id(id).await?
            .ok_or(Error::NotFound)
    }
}

// Test with mock
#[cfg(test)]
mod tests {
    struct MockUserRepo {
        users: HashMap<u64, User>,
    }
    
    #[async_trait]
    impl UserRepository for MockUserRepo {
        async fn find_by_id(&self, id: u64) -> Result<Option<User>, DbError> {
            Ok(self.users.get(&id).cloned())
        }
        // ...
    }
    
    #[tokio::test]
    async fn test_get_user_found() {
        let mut mock = MockUserRepo { users: HashMap::new() };
        mock.users.insert(1, User { id: 1, name: "Alice".into() });
        
        let service = UserService { repo: mock };
        let user = service.get_user(1).await.unwrap();
        
        assert_eq!(user.name, "Alice");
    }
    
    #[tokio::test]
    async fn test_get_user_not_found() {
        let mock = MockUserRepo { users: HashMap::new() };
        let service = UserService { repo: mock };
        
        let result = service.get_user(999).await;
        assert!(matches!(result, Err(Error::NotFound)));
    }
}
```

## mockall Crate

```rust
use mockall::*;
use mockall::predicate::*;

#[automock]
trait Database: Send + Sync {
    // Edition 2024: no #[async_trait] needed for async fn in traits
    async fn query(&self, sql: &str) -> Result<Vec<Row>, Error>;
}

#[tokio::test]
async fn test_with_mockall() {
    let mut mock = MockDatabase::new();
    
    mock.expect_query()
        .with(eq("SELECT 1"))
        .times(1)
        .returning(|_| Ok(vec![Row::new()]));
    
    let result = mock.query("SELECT 1").await;
    assert!(result.is_ok());
}
```

## wiremock-rs (HTTP Mocking)

```rust
use wiremock::{MockServer, Mock, ResponseTemplate};
use wiremock::matchers::{method, path};

#[tokio::test]
async fn test_http_client() {
    // Start a mock HTTP server
    let mock_server = MockServer::start().await;
    
    // Set up expected request and response
    Mock::given(method("GET"))
        .and(path("/api/users/1"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(serde_json::json!({
                "id": 1,
                "name": "Alice"
            })))
        .mount(&mock_server)
        .await;
    
    // Client uses the mock server URL
    let client = ApiClient::new(&mock_server.uri());
    let user = client.get_user(1).await.unwrap();
    
    assert_eq!(user.name, "Alice");
}
```

## Testing Error Paths

```rust
trait HttpClient: Send + Sync {
    async fn get(&self, url: &str) -> Result<Response, HttpError>;
}

struct FailingClient;

impl HttpClient for FailingClient {
    async fn get(&self, _url: &str) -> Result<Response, HttpError> {
        Err(HttpError::Timeout)  // Always fails
    }
}

#[tokio::test]
async fn test_handles_timeout() {
    let client = FailingClient;
    let service = ApiService { client };
    
    let result = service.fetch_data().await;
    assert!(matches!(result, Err(Error::NetworkError(_))));
}
```

## Dynamic Dispatch Alternative

```rust
// When you don't want generics everywhere
struct UserService {
    repo: Box<dyn UserRepository>,
}

impl UserService {
    fn new(repo: impl UserRepository + 'static) -> Self {
        Self { repo: Box::new(repo) }
    }
}

// Slight runtime cost but cleaner API
```

## Cargo.toml

```toml
[dev-dependencies]
mockall = "0.14"
wiremock = "0.7"  # HTTP mocking
```

## See Also

- [api-sealed-trait](./api-sealed-trait.md) - Trait design
- [test-mockall-mocking](./test-mockall-mocking.md) - Mockall details
- [test-proptest-properties](./test-proptest-properties.md) - Property-based testing
- [proj-lib-main-split](./proj-lib-main-split.md) - Testable architecture
