# api-builder-pattern

> Use a builder when construction has several optional settings, validation, or staged configuration

## Why It Matters

Builders replace long positional constructors with named configuration steps and give construction logic a natural place for defaults and validation. They are most useful when a type has several optional parameters or when construction may fail.

Do not introduce a builder automatically for every struct. A small constructor with a few obvious required arguments is usually clearer.

## Good: Fallible Builder with Required and Optional Inputs

```rust
use std::time::Duration;

#[derive(Debug, PartialEq)]
struct Client {
    base_url: String,
    timeout: Duration,
    max_retries: u32,
}

#[derive(Default)]
#[must_use = "builders do nothing unless you call build()"]
struct ClientBuilder {
    base_url: Option<String>,
    timeout: Option<Duration>,
    max_retries: Option<u32>,
}

impl ClientBuilder {
    fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = Some(url.into());
        self
    }

    fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    fn max_retries(mut self, max_retries: u32) -> Self {
        self.max_retries = Some(max_retries);
        self
    }

    fn build(self) -> Result<Client, &'static str> {
        Ok(Client {
            base_url: self.base_url.ok_or("base_url is required")?,
            timeout: self.timeout.unwrap_or(Duration::from_secs(30)),
            max_retries: self.max_retries.unwrap_or(3),
        })
    }
}

fn main() {
    let client = ClientBuilder::default()
        .base_url("https://api.example.com")
        .timeout(Duration::from_secs(10))
        .max_retries(5)
        .build()
        .unwrap();

    assert_eq!(client.max_retries, 5);
}
```

Use `Result` from `build()` when validity cannot be established solely through the setter API.

## Infallible Builders

If every builder state can be completed into a valid value, `build()` can return the value directly.

```rust
#[derive(Default)]
struct LabelBuilder {
    text: String,
    uppercase: bool,
}

impl LabelBuilder {
    fn text(mut self, text: impl Into<String>) -> Self {
        self.text = text.into();
        self
    }

    fn uppercase(mut self, value: bool) -> Self {
        self.uppercase = value;
        self
    }

    fn build(self) -> String {
        if self.uppercase {
            self.text.to_uppercase()
        } else {
            self.text
        }
    }
}

fn main() {
    assert_eq!(LabelBuilder::default().text("rust").uppercase(true).build(), "RUST");
}
```

## Consuming vs Borrowing Setters

Consuming setters (`self -> Self`) compose naturally in chains and are common for one-shot builders. Borrowing setters (`&mut self -> &mut Self`) can be useful when configuration is performed conditionally over multiple statements. Choose deliberately; neither style is universally superior.

## Required Fields: Runtime Validation or Typestate

A conventional builder can represent required fields as `Option<T>` and report omissions from `build()`. Typestate builders can instead make missing required fields a compile-time error, but they produce more types and more complex signatures. Use that complexity when the compile-time guarantee is worth it.

For ordinary application builders, a macro crate can generate this machinery reliably.

## `bon`

`bon` provides `#[derive(Builder)]` for structs and `#[builder]` for functions and methods. Its generated builders use typestate so required members and duplicate setter calls are checked at compile time.

```rust
use bon::Builder;

#[derive(Builder)]
struct Request {
    #[builder(into)]
    url: String,
    #[builder(default = 30)]
    timeout_secs: u64,
}

fn main() {
    let request = Request::builder()
        .url("https://example.com")
        .timeout_secs(10)
        .build();

    assert_eq!(request.timeout_secs, 10);
}
```

Use a dependency such as `bon` when its generated API matches your needs; do not justify it with unverified claims about ecosystem dominance or universal compile-time performance.

## `#[must_use]`

Marking the builder type `#[must_use]` is useful when silently dropping a configured builder is probably a mistake. Method-level `#[must_use]` can also help with APIs whose setters consume and return `Self`, but do not add attributes mechanically where they create noise without catching realistic mistakes.

## When a Builder Is Overkill

Prefer a constructor when required inputs are few and obvious:

```rust
struct User {
    id: u64,
    name: String,
}

impl User {
    fn new(id: u64, name: impl Into<String>) -> Self {
        Self { id, name: name.into() }
    }
}

fn main() {
    let _user = User::new(7, "Ada");
}
```

A builder should improve the call site or enforce construction policy, not merely add ceremony.

## Practical Guidance

- Use builders for several optional settings, validation, or staged construction.
- Keep simple constructors simple.
- Return `Result` from `build()` when runtime validation can fail.
- Use typestate when compile-time construction guarantees justify the extra type complexity.
- Choose consuming or borrowing setters according to intended usage.
- Prefer generated builders when a maintained crate's API fits the project.

## See Also

- [api-bon-builder](./api-bon-builder.md) - bon crate builder
- [api-builder-must-use](./api-builder-must-use.md) - Add #[must_use] to builders
- [api-typestate](./api-typestate.md) - Compile-time state machines
- [api-impl-into](./api-impl-into.md) - Ownership-taking conversion parameters
