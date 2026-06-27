# api-bon-builder

> Use the `bon` crate (v3.9, `elastio/bon`) for ergonomic, compile-time safe builders

**Rule**: `api-bon-builder`

## Why It Matters

Hand-rolled builders require significant boilerplate and are easy to get wrong — missing `#[must_use]`, unenforced required fields, no `Into` conversion support, no fallible/async construction. The `bon` crate (community-standard since 2025) solves all of these with a single `#[derive(Builder)]` on structs or `#[builder]` on functions/methods. It uses trait-based typestate with human-readable types, supports opt-in `Into` conversions, fallible and async builders, and compiles up to 10× faster than `derive_builder`.

## Bad

```rust
// Hand-rolled builder — 20+ lines of boilerplate, no compile-time safety
#[must_use]
pub struct UserBuilder {
    name: Option<String>,
    email: Option<String>,
    age: Option<u16>,
}

impl UserBuilder {
    pub fn new() -> Self {
        Self { name: None, email: None, age: None }
    }

    pub fn name(mut self, name: impl Into<String>) -> Self {
        self.name = Some(name.into());
        self
    }

    pub fn email(mut self, email: impl Into<String>) -> Self {
        self.email = Some(email.into());
        self
    }

    pub fn age(mut self, age: u16) -> Self {
        self.age = Some(age);
        self
    }

    pub fn build(self) -> Result<User, &'static str> {
        Ok(User {
            name: self.name.ok_or("name is required")?,
            email: self.email.ok_or("email is required")?,
            age: self.age.ok_or("age is required")?,
        })
    }
}
```

## Good

```rust
use bon::Builder;

// 1. Struct-level builder — one derive, no boilerplate
#[derive(Builder)]
pub struct User {
    #[builder(into)]     // auto-convert &str → String
    name: String,

    #[builder(into)]
    email: String,

    #[builder(default = 18)]
    age: u16,
}

// Usage with compile-time required field checking
let user = User::builder()
    .name("Alice")        // &str auto-converted via Into
    .email("alice@example.com")
    .age(30)
    .build();

// Missing required field → compile error:
// User::builder().name("Bob").build();  // Error: email is required


// 2. Function-level builder — decouples builder from struct internals
#[bon::builder]
fn connect(
    host: &str,
    port: u16,
    #[builder(default = 5)]
    retries: u32,
) -> Result<Connection, Error> {
    // host and port are required at compile time
    // retries has a default
    // ...
}

let conn = connect()
    .host("localhost")
    .port(8080)
    .retries(3)  // optional
    .call()?;


// 3. Fallible builder — build can return Result
#[derive(Builder)]
pub struct Server {
    #[builder(into)]
    host: String,
    port: u16,
}

impl Server {
    fn build(self) -> Result<Self, ConfigError> {
        // Custom validation logic
        if self.port == 0 {
            return Err(ConfigError::InvalidPort);
        }
        Ok(self)
    }
}


// 4. Async builder — combine with async fn
#[bon::builder]
pub async fn fetch_data(
    url: &str,
    #[builder(default = 30)]
    timeout_secs: u64,
) -> Result<Response, Error> {
    // ...
}

let resp = fetch_data()
    .url("https://api.example.com")
    .timeout_secs(60)
    .call()
    .await?;
```

## Key Features

| Feature | `bon` | Hand-rolled | `derive_builder` |
|---------|-------|-------------|------------------|
| Struct builder | `#[derive(Builder)]` | Manual | `#[derive(Builder)]` |
| Function/method builder | `#[builder]` on fn | N/A | N/A |
| Typestate required fields | Built-in | Manual | Gaps |
| `Into` conversions | `#[builder(into)]` | Manual | Manual |
| Fallible build | `.build()` → impl Trait | Manual | Poor |
| Async build | `.call().await` | Manual | N/A |
| Compile speed (relative) | Fastest | N/A | ~10× slower |

## Migration from `derive_builder`

```rust
// From derive_builder:
// #[derive(derive_builder::Builder)]
// pub struct Config { ... }

// To bon:
#[derive(bon::Builder)]
pub struct Config {
    #[builder(into)]
    pub name: String,

    #[builder(default = 8080)]
    pub port: u16,
}
// bon catches missing required fields at compile time
// derive_builder would panic at runtime
```

## See Also

- [api-builder-pattern](./api-builder-pattern.md) — Builder pattern fundamentals
- [api-builder-must-use](./api-builder-must-use.md) — #[must_use] on builder methods
- [api-typestate](./api-typestate.md) — Compile-time state machines via typestate

## References

- [bon crate](https://bon-rs.com)
- [bon documentation — overview](https://bon-rs.com/guide/overview)
- [api-builder-pattern](./api-builder-pattern.md) — Builder pattern fundamentals
- [api-typestate](./api-typestate.md) — Typestate pattern
- [api-builder-must-use](./api-builder-must-use.md) — must_use on builders
