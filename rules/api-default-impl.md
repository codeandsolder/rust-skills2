# api-default-impl

> Implement `Default` only when the type has a sensible canonical default value

## Why It Matters

`Default` integrates with `Option::unwrap_or_default()`, `#[derive(Default)]`, struct update syntax, and generic code requiring `T: Default`. That convenience is useful only when `default()` represents a meaningful value rather than an arbitrary placeholder.

A public `Default` implementation is a semantic commitment. Callers may rely on what the default means even if they should not rely on every field value remaining identical forever.

## Good: A Meaningful Configuration Default

```rust
use std::time::Duration;

#[derive(Debug, PartialEq)]
struct Config {
    timeout: Duration,
    retries: u32,
    verbose: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(30),
            retries: 3,
            verbose: false,
        }
    }
}

fn main() {
    let config = Config::default();
    assert_eq!(config.retries, 3);

    let custom = Config {
        retries: 5,
        ..Config::default()
    };
    assert_eq!(custom.retries, 5);
}
```

The important property is not that every field uses its field type's default. It is that the resulting `Config` is a legitimate, unsurprising baseline configuration.

## Derive When Field Defaults Are the Intended Semantics

```rust
#[derive(Debug, Default, PartialEq)]
struct Counters {
    accepted: u64,
    rejected: u64,
}

fn main() {
    assert_eq!(Counters::default(), Counters { accepted: 0, rejected: 0 });
}
```

Use a manual implementation when a meaningful domain default differs from field-wise defaults.

## Do Not Invent Defaults for Required Identity

```rust
#[derive(Debug)]
struct UserId(u64);

#[derive(Debug)]
struct User {
    id: UserId,
    name: String,
}

impl User {
    fn new(id: UserId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }
}

fn main() {
    let user = User::new(UserId(7), "Ada");
    assert_eq!(user.id.0, 7);
}
```

If a valid value requires an identity, path, key, address, or other mandatory domain input, forcing a fake `Default` usually hides missing information rather than improving ergonomics.

## Builders Can Default Optional Fields

The final domain type does not need to implement `Default` just because its builder has defaults for optional settings.

```rust
#[derive(Debug, PartialEq)]
struct Server {
    host: String,
    port: u16,
    workers: usize,
}

#[derive(Debug)]
struct ServerBuilder {
    host: Option<String>,
    port: u16,
    workers: usize,
}

impl Default for ServerBuilder {
    fn default() -> Self {
        Self {
            host: None,
            port: 8080,
            workers: 4,
        }
    }
}

impl ServerBuilder {
    fn host(mut self, host: impl Into<String>) -> Self {
        self.host = Some(host.into());
        self
    }

    fn port(mut self, port: u16) -> Self {
        self.port = port;
        self
    }

    fn build(self) -> Result<Server, &'static str> {
        let host = self.host.ok_or("host is required")?;
        Ok(Server {
            host,
            port: self.port,
            workers: self.workers,
        })
    }
}

fn main() {
    let server = ServerBuilder::default()
        .host("0.0.0.0")
        .port(3000)
        .build()
        .unwrap();

    assert_eq!(server.port, 3000);
}
```

Here the builder has sensible defaults for optional policy choices while `host` remains explicitly required.

## Enum Defaults

An enum can derive `Default` by marking one unit variant with `#[default]`:

```rust
#[derive(Debug, Default, PartialEq, Eq)]
enum State {
    #[default]
    Idle,
    Processing,
    Failed(String),
}

fn main() {
    assert_eq!(State::default(), State::Idle);
}
```

Choose the default variant because it is the canonical initial/empty state, not merely because derive supports it.

## Generic Bounds

Require `T: Default` only when the algorithm genuinely needs to construct an unspecified `T`.

```rust
fn value_or_default<T: Default>(value: Option<T>) -> T {
    value.unwrap_or_default()
}

fn main() {
    assert_eq!(value_or_default::<String>(None), "");
}
```

Unnecessary `Default` bounds reduce the set of usable types and can accidentally force callers to invent meaningless defaults.

## Practical Guidance

- Implement `Default` when there is a sensible canonical value.
- Prefer derive when field-wise defaults are exactly the intended semantics.
- Use a manual implementation for meaningful domain-specific defaults.
- Do not use `Default` to fabricate required identity or mandatory input.
- A builder may implement `Default` even when the final built type should not.
- Avoid adding `T: Default` bounds merely for convenience.

## See Also

- [api-builder-pattern](./api-builder-pattern.md) - Building complex types
- [api-common-traits](./api-common-traits.md) - Semantic trait choices
- [api-from-not-into](./api-from-not-into.md) - Conversion traits
