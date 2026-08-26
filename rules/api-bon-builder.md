# api-bon-builder

> Use `bon` when typestate builders for structs or functions improve the API; account for proc-macro and typestate compile cost

**Rule**: `api-bon-builder`

## Why It Matters

`bon` can generate typestate builders for structs, functions, and methods, enforcing required members at compile time and supporting features such as `#[builder(into)]`, defaults, async functions, and builder-style constructors.

It is a useful option, not a universal community standard, and its stronger typestate machinery has compile-time cost. Current Bon benchmarks explicitly show more compile-time overhead than simpler builder crates such as `derive_builder`; choose it for API ergonomics and static guarantees, not because it supposedly compiles "10× faster".

## Struct Builder

```rust
use bon::Builder;

#[derive(Builder)]
struct User {
    #[builder(into)]
    name: String,
    #[builder(into)]
    email: String,
    #[builder(default = 18)]
    age: u16,
}

let user = User::builder()
    .name("Alice")
    .email("alice@example.com")
    .age(30)
    .build();
```

Required members are represented in the generated builder state, so omitting one is a compile-time error.

## Function Builder and Fallible Construction

When construction itself is fallible, put `#[builder]` on the fallible constructor/function. The generated finishing method then returns that function's `Result`.

```rust
use bon::bon;

struct Server {
    host: String,
    port: u16,
}

#[derive(Debug)]
struct ConfigError;

#[bon]
impl Server {
    #[builder]
    fn new(#[builder(into)] host: String, port: u16) -> Result<Self, ConfigError> {
        if port == 0 {
            return Err(ConfigError);
        }
        Ok(Self { host, port })
    }
}

let server: Result<Server, ConfigError> = Server::builder()
    .host("localhost")
    .port(8080)
    .build();
assert!(server.is_ok());
```

Do not derive a struct builder and then add an unrelated inherent method named `build`; that does not turn the generated builder into a fallible builder.

## Async Function Builder

```rust
#[bon::builder]
async fn fetch_data(
    url: &str,
    #[builder(default = 30)] timeout_secs: u64,
) -> Result<Response, Error> {
    // ...
}

let response = fetch_data()
    .url("https://example.com")
    .timeout_secs(10)
    .call()
    .await?;
```

## Choosing a Builder Approach

- Use Bon when compile-time required-member tracking and function/method builders materially improve the API.
- A small hand-written builder can be clearer for tiny stable APIs.
- Simpler derive crates may compile faster when typestate guarantees are unnecessary.
- Benchmark build times in macro-heavy workspaces instead of relying on generic performance claims.

## See Also

- [api-builder-pattern](./api-builder-pattern.md) — builder fundamentals
- [api-typestate](./api-typestate.md) — typestate tradeoffs
- [Bon documentation](https://bon-rs.com)
- [Bon compilation benchmarks](https://bon-rs.com/guide/benchmarks/compilation)
