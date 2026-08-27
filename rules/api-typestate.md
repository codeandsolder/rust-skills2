# api-typestate

> Use typestate when compile-time state transitions materially simplify or strengthen an API

## Why It Matters

Typestate represents important runtime states as different Rust types. Methods can then exist only for states where they are valid, so some invalid operation sequences become compile-time errors instead of runtime checks.

That guarantee is valuable for protocols, staged resource initialization, transactions, and builders with important required fields. It is not free: state-specific types can complicate storage, trait bounds, type inference, error paths, and APIs that need to choose or erase state dynamically.

Use typestate when the state transition is an important API invariant, not merely because a value happens to have modes.

## Good: Operations Exist Only in Valid States

```rust
#[derive(Debug)]
struct Disconnected;

#[derive(Debug)]
struct Connected {
    endpoint: String,
}

#[derive(Debug)]
struct Connection<State> {
    state: State,
}

impl Connection<Disconnected> {
    fn new() -> Self {
        Self { state: Disconnected }
    }

    fn connect(self, endpoint: impl Into<String>) -> Connection<Connected> {
        Connection {
            state: Connected {
                endpoint: endpoint.into(),
            },
        }
    }
}

impl Connection<Connected> {
    fn send(&self, payload: &[u8]) -> usize {
        let _endpoint = &self.state.endpoint;
        payload.len()
    }
}

fn main() {
    let connection = Connection::new().connect("server.example");
    assert_eq!(connection.send(b"hello"), 5);
}
```

There is no `send` method on `Connection<Disconnected>`. The type transition produced by `connect` makes the valid sequence explicit.

## Good: Builder Typestate for a Required Field

```rust
#[derive(Debug)]
struct MissingUrl;

#[derive(Debug)]
struct HasUrl(String);

#[derive(Debug)]
struct Request {
    url: String,
    timeout_secs: u64,
}

#[derive(Debug)]
struct RequestBuilder<State> {
    state: State,
    timeout_secs: u64,
}

impl RequestBuilder<MissingUrl> {
    fn new() -> Self {
        Self {
            state: MissingUrl,
            timeout_secs: 30,
        }
    }

    fn url(self, url: impl Into<String>) -> RequestBuilder<HasUrl> {
        RequestBuilder {
            state: HasUrl(url.into()),
            timeout_secs: self.timeout_secs,
        }
    }
}

impl<State> RequestBuilder<State> {
    fn timeout_secs(mut self, timeout_secs: u64) -> Self {
        self.timeout_secs = timeout_secs;
        self
    }
}

impl RequestBuilder<HasUrl> {
    fn build(self) -> Request {
        Request {
            url: self.state.0,
            timeout_secs: self.timeout_secs,
        }
    }
}

fn main() {
    let request = RequestBuilder::new()
        .timeout_secs(10)
        .url("https://example.com")
        .build();

    assert_eq!(request.url, "https://example.com");
    assert_eq!(request.timeout_secs, 10);
}
```

`build()` is available only after `url()` changes the state type. This can be worthwhile when a missing required field should be impossible by construction.

## Runtime Validation Can Be Simpler

For many builders, storing required fields as `Option<T>` and returning an error from `build()` is easier to understand and maintain.

```rust
#[derive(Debug)]
struct Request {
    url: String,
}

#[derive(Default)]
struct RequestBuilder {
    url: Option<String>,
}

impl RequestBuilder {
    fn url(mut self, url: impl Into<String>) -> Self {
        self.url = Some(url.into());
        self
    }

    fn build(self) -> Result<Request, &'static str> {
        Ok(Request {
            url: self.url.ok_or("url is required")?,
        })
    }
}

fn main() {
    assert!(RequestBuilder::default().build().is_err());
    assert!(RequestBuilder::default().url("https://example.com").build().is_ok());
}
```

Prefer this simpler design when a runtime construction error is acceptable and typestate would mostly expose generic machinery to users.

## State Transitions That Can Fail

A typestate transition can still return `Result`. The type system can express which transition is being attempted without pretending the operation itself cannot fail.

```rust
#[derive(Debug)]
struct Closed;

#[derive(Debug)]
struct Open;

#[derive(Debug)]
struct File<State> {
    name: String,
    state: State,
}

impl File<Closed> {
    fn open(self) -> Result<File<Open>, &'static str> {
        if self.name.is_empty() {
            return Err("empty file name");
        }

        Ok(File {
            name: self.name,
            state: Open,
        })
    }
}

impl File<Open> {
    fn read(&self) -> &[u8] {
        let _ = &self.state;
        b"contents"
    }
}

fn main() {
    let file = File {
        name: "data.txt".to_owned(),
        state: Closed,
    };

    let file = file.open().unwrap();
    assert_eq!(file.read(), b"contents");
}
```

Typestate prevents calling `read` before a successful transition, while `Result` still models I/O or validation failure.

## Generated Builder Typestate

Builder crates can hide most of the state-marker machinery. For example, `bon` generates a typestate builder in which required members must be supplied before `build()` is available.

```rust
use bon::Builder;

#[derive(Builder)]
struct Query {
    #[builder(into)]
    table: String,
    #[builder(into)]
    filter: Option<String>,
    #[builder(default = 100)]
    limit: usize,
}

fn main() {
    let query = Query::builder()
        .table("users")
        .filter("active")
        .limit(50)
        .build();

    assert_eq!(query.table, "users");
    assert_eq!(query.filter.as_deref(), Some("active"));
    assert_eq!(query.limit, 50);
}
```

Generated typestate is often a good fit for builders because callers interact mostly with ordinary setter methods rather than naming the generated state types directly.

## Costs and Escape Hatches

Typestate becomes awkward when code must store values in several states in one homogeneous collection, select a state at runtime, or pass partially progressed values through generic infrastructure. At that point an enum, runtime state field, trait object, or another form of type erasure may be clearer.

Do not force typestate through those boundaries merely to eliminate every runtime check. Compile-time guarantees are useful when they make the API easier to use correctly overall.

## Practical Guidance

- Use typestate for important ordered transitions and state-specific capabilities.
- Let state-changing methods consume `self` when the old state should no longer be usable.
- Returning `Result<NextState, E>` is normal when the transition itself can fail.
- Prefer runtime validation when typestate adds more public complexity than safety or usability.
- Generated typestate is especially useful for builders with required fields.
- Avoid unrelated feature claims: trait-object upcasting and other language features do not by themselves make an API a typestate design.

## See Also

- [api-bon-builder](./api-bon-builder.md) - Generated builder typestate
- [api-builder-pattern](./api-builder-pattern.md) - Builder tradeoffs
- [api-parse-dont-validate](./api-parse-dont-validate.md) - Type-driven invariants
- [api-sealed-trait](./api-sealed-trait.md) - Restricting trait implementations
