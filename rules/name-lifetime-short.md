# name-lifetime-short

> Keep lifetime parameter names short and lowercase; use `'a` by default and descriptive names such as `'src` when they add real meaning

## Why It Matters

Rust's API Guidelines recommend short lowercase lifetime names, usually a single letter. A single unconstrained borrow is conventionally `'a`; multiple generic lifetimes often use `'a`, `'b`, and so on.

Descriptive short names such as `'src`, `'ctx`, or Serde's `'de` are useful when the lifetime has a semantic role that matters to readers. Longer names are not wrong Rust—the goal is readable signatures, not minimizing character count at any cost.

## Prefer Elision When the Relationship Is Obvious

```rust
fn first_word(input: &str) -> &str {
    input.split_whitespace().next().unwrap_or("")
}

struct User {
    name: String,
}

impl User {
    fn name(&self) -> &str {
        &self.name
    }
}

fn main() {
    assert_eq!(first_word("hello world"), "hello");
    let user = User { name: "Ada".to_owned() };
    assert_eq!(user.name(), "Ada");
}
```

Do not write explicit lifetimes merely to demonstrate that they exist when ordinary lifetime elision already expresses the contract.

## Use `'a` for a Simple Named Relationship

```rust
struct Parser<'a> {
    source: &'a str,
}

impl<'a> Parser<'a> {
    fn source(&self) -> &'a str {
        self.source
    }
}

fn main() {
    let text = String::from("input");
    let parser = Parser { source: &text };
    assert_eq!(parser.source(), "input");
}
```

A verbose name such as `'parser_instance_lifetime` adds noise here without distinguishing anything.

## Multiple Lifetimes May Benefit from Roles

Single letters are concise when the relationships are easy to see:

```rust
fn choose_first<'a, 'b>(first: &'a str, _second: &'b str) -> &'a str {
    first
}

fn main() {
    assert_eq!(choose_first("a", "b"), "a");
}
```

When a lifetime represents a stable domain concept, a short descriptive name can be clearer:

```rust
struct Token<'src> {
    text: &'src str,
}

struct Query<'ctx> {
    context: &'ctx str,
}

fn main() {
    let token = Token { text: "name" };
    let query = Query { context: "database" };
    assert_eq!(token.text, "name");
    assert_eq!(query.context, "database");
}
```

Do not mechanically rename meaningful `'src`/`'ctx` lifetimes to `'a` just to satisfy a style slogan.

## Serde's `'de` Is a Trait Lifetime, Not a Struct-Lifetime Recipe

Serde conventionally names the **deserializer input lifetime** `'de`:

```text
trait Deserialize<'de> { ... }
trait Deserializer<'de> { ... }
```

But a type that **derives** `Deserialize` and borrows from its input should not itself declare a lifetime parameter named `'de`. Serde's derive generates its own `'de` lifetime and explicitly rejects that collision for borrowed types.

Use another lifetime on the data type, commonly `'a`:

```rust
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Request<'a> {
    #[serde(borrow)]
    name: &'a str,
    #[serde(borrow)]
    tags: Vec<&'a str>,
}

fn main() {
    let input = r#"{"name":"Ada","tags":["rust","serde"]}"#;
    let request: Request<'_> = serde_json::from_str(input).unwrap();
    assert_eq!(request.name, "Ada");
    assert_eq!(request.tags, vec!["rust", "serde"]);
}
```

For a hand-written `Deserialize` impl, `'de` appropriately names the deserializer lifetime, with bounds relating it to lifetimes on the target type as needed.

## `'static` Is a Lifetime Value, Not a Generic Naming Choice

`'static` has special semantics: it means data can live for the entire program (or, for bounds, that the value contains no non-static borrowed data). It is not just another name in a sequence like `'a`, `'b`.

```rust
const MESSAGE: &'static str = "ready";

fn main() {
    assert_eq!(MESSAGE, "ready");
}
```

Do not use `'static` merely because a descriptive lifetime name feels inconvenient.

## Avoid Invalid Independent Output Lifetimes

A returned borrow normally must be tied to some input/source lifetime. This is invalid because `'out` has no source that can provide the returned reference:

```rust,compile_fail
fn parse<'input, 'out>(input: &'input str) -> &'out str {
    input
}
```

The correct signature ties the output to the input (or relies on elision):

```rust
fn parse<'a>(input: &'a str) -> &'a str {
    input
}

fn main() {
    assert_eq!(parse("value"), "value");
}
```

## Practical Guidance

- Elide lifetimes when Rust's elision rules express the relationship clearly.
- Use `'a`, `'b`, etc. for ordinary generic borrow relationships.
- Use short descriptive names such as `'src` or `'ctx` when they genuinely clarify roles.
- Reserve `'de` for Serde's deserializer lifetime; do not name a borrowed derive target's own lifetime `'de`.
- Treat `'static` as a semantic lifetime, not a naming convention.
- Prefer names that make lifetime relationships understandable rather than enforcing one-character names mechanically.

## See Also

- [own-lifetime-elision](./own-lifetime-elision.md) - Lifetime elision and Edition 2024 RPIT capture
- [name-type-param-single](./name-type-param-single.md) - Generic type parameter naming
- [own-borrow-over-clone](./own-borrow-over-clone.md) - Borrowing patterns
