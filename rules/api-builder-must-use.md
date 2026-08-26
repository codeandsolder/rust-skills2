# api-builder-must-use

> Mark consuming builder methods or the builder type `#[must_use]` when ignoring the returned builder is likely a bug

## Why It Matters

A common builder style takes `self` and returns a modified `Self`. Calling such a method without using the returned value consumes and drops that builder. `#[must_use]` turns an otherwise easy-to-miss mistake into a compiler warning.

This advice specifically applies when ignoring the return value is suspicious. Builders whose setters take `&mut self` mutate in place and do not need `#[must_use]` for this reason.

## Bad

```rust
use std::time::Duration;

#[derive(Default)]
struct RequestBuilder {
    timeout: Option<Duration>,
}

impl RequestBuilder {
    fn timeout(mut self, duration: Duration) -> Self {
        self.timeout = Some(duration);
        self
    }
}

let request = RequestBuilder::default();
request.timeout(Duration::from_secs(30));
// `request` was consumed and dropped; without must_use this can be easy to miss.
```

## Good

```rust
use std::time::Duration;

#[derive(Debug, PartialEq, Eq)]
struct Request {
    url: String,
    timeout: Option<Duration>,
    headers: Vec<(String, String)>,
}

#[must_use = "a RequestBuilder has no effect until build() is called"]
struct RequestBuilder {
    url: String,
    timeout: Option<Duration>,
    headers: Vec<(String, String)>,
}

impl RequestBuilder {
    fn new(url: impl Into<String>) -> Self {
        Self {
            url: url.into(),
            timeout: None,
            headers: Vec::new(),
        }
    }

    #[must_use = "use the returned builder"]
    fn timeout(mut self, duration: Duration) -> Self {
        self.timeout = Some(duration);
        self
    }

    #[must_use = "use the returned builder"]
    fn header(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.push((key.into(), value.into()));
        self
    }

    fn build(self) -> Request {
        Request {
            url: self.url,
            timeout: self.timeout,
            headers: self.headers,
        }
    }
}

let request = RequestBuilder::new("https://api.example.com")
    .timeout(Duration::from_secs(30))
    .header("Authorization", "Bearer token")
    .build();

assert_eq!(request.timeout, Some(Duration::from_secs(30)));
assert_eq!(request.headers.len(), 1);
```

Putting `#[must_use]` on the builder type gives broad protection for unused builder values. Method-level annotations can provide more targeted messages or cover APIs where the type itself should not be must-use.

## Reassignment Is Also Valid

```rust
#[must_use]
#[derive(Default)]
struct Builder {
    retries: usize,
}

impl Builder {
    #[must_use]
    fn retries(mut self, retries: usize) -> Self {
        self.retries = retries;
        self
    }
}

let builder = Builder::default();
let builder = builder.retries(3);
assert_eq!(builder.retries, 3);
```

Chaining is usually terser, but reassignment makes the ownership behavior equally explicit.

## Do Not Add `must_use` Mechanically

`#[must_use]` is useful when silently discarding a value is probably a mistake. Overusing it creates warning noise and teaches users to suppress warnings indiscriminately. Apply it to the builder type or consuming setters when it communicates a real API contract.

Builder frameworks may already annotate generated types/methods. Check generated/API documentation before layering redundant attributes on macro-generated builders.

## Clippy

```toml
[lints.clippy]
must_use_candidate = "warn"
return_self_not_must_use = "warn"
```

These are review aids, not substitutes for deciding whether ignoring the value is actually erroneous for that API.

## See Also

- [api-builder-pattern](./api-builder-pattern.md) - Builder pattern best practices
- [api-must-use](./api-must-use.md) - General must_use guidelines
- [api-bon-builder](./api-bon-builder.md) - Typestate/function builders with Bon
