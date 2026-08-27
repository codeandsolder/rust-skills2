# name-type-param-single

> Use concise `UpperCamelCase` type-parameter names—often `T`, `E`, `K`, `V`, but descriptive names are appropriate when they improve clarity

## Why It Matters

Rust's API Guidelines recommend **concise `UpperCamelCase`** names for type parameters and say they are **usually** a single uppercase letter such as `T`. That is a convention, not a rule that every generic parameter must be one character.

Single-letter names work well when the role is conventional and visible from context. Descriptive type-parameter names are often clearer in APIs with several independent roles or where a single letter would force readers to decode the signature.

## Conventional Single-Letter Parameters

```rust
struct Container<T> {
    items: Vec<T>,
}

enum Outcome<T, E> {
    Ok(T),
    Err(E),
}

struct Table<K, V> {
    entries: Vec<(K, V)>,
}

fn main() {
    let values = Container { items: vec![1, 2, 3] };
    assert_eq!(values.items.len(), 3);

    let _: Outcome<u32, &str> = Outcome::Ok(42);
    let table = Table { entries: vec![("a", 1)] };
    assert_eq!(table.entries.len(), 1);
}
```

`T`, `E`, `K`, and `V` are immediately recognizable when the surrounding abstraction makes their roles obvious.

## Common Letters Are Conventions, Not Reserved Meanings

Typical uses include:

| Name | Common role |
|---|---|
| `T`, `U` | generic value/type roles |
| `E` | error type |
| `K`, `V` | map key/value |
| `F` | function/closure |
| `I` | iterator/input, depending on context |
| `R` | result/reader/return-like role, depending on context |
| `S` | state/hasher/storage, depending on context |
| `A` | allocator or another clearly local role |

Do not assume a letter has one universal meaning across Rust. The local API defines the role.

## Descriptive Names Can Be Better

When several generic roles would otherwise be cryptic, concise descriptive names are idiomatic too:

```rust
struct Pipeline<Input, Output> {
    transform: fn(Input) -> Output,
}

impl<Input, Output> Pipeline<Input, Output> {
    fn run(&self, input: Input) -> Output {
        (self.transform)(input)
    }
}

fn main() {
    let pipeline = Pipeline {
        transform: |value: u32| value.to_string(),
    };
    assert_eq!(pipeline.run(42), "42");
}
```

`Input` and `Output` make this public type easier to read than an arbitrary `Pipeline<I, O>` if those roles appear repeatedly in a larger API.

Avoid redundant suffixes such as `InputType` or `ElementType` when `Input` or `Element` already makes clear that the identifier names a type parameter.

## Trait Bounds Do Not Require Long Parameter Names

Move complicated bounds into a `where` clause, but choose parameter names independently from bound complexity:

```rust
use std::fmt::Debug;

fn passthrough<T, E>(value: T) -> Result<T, E>
where
    T: Clone + Debug + Send + Sync,
    E: std::error::Error,
{
    Ok(value)
}

fn main() {
    let result: Result<u32, std::io::Error> = passthrough(7);
    assert_eq!(result.unwrap(), 7);
}
```

A long `where` clause does not by itself justify renaming `T` to `CloneDebugSendSyncType`.

## Descriptive Names Still Follow Type Casing

Type parameters are type-level identifiers, so descriptive names use `UpperCamelCase`:

```rust
struct Query<Database, Row> {
    database: Database,
    marker: std::marker::PhantomData<Row>,
}

fn main() {
    let query: Query<&str, String> = Query {
        database: "primary",
        marker: std::marker::PhantomData,
    };
    assert_eq!(query.database, "primary");
}
```

Lowercase names such as `element_type` do not follow Rust's type-parameter casing convention. Lifetimes are syntactically distinct because they include the leading apostrophe (`'a`).

## Generic Roles at Different Scales

A useful rule of thumb:

- small local helper with one obvious generic type → `T`;
- `Result`-like abstraction → `T, E`;
- map-like abstraction → `K, V`;
- closure adapter → often `F` plus whatever item/output names fit;
- public type with several domain roles → consider concise descriptive names such as `Request`, `Response`, `Backend`, `Storage`.

Consistency with neighboring APIs matters more than forcing every generic signature into an alphabetic sequence.

## Do Not Rename Stable Public Parameters Casually

Generic parameter names appear in documentation and can be referenced by users in prose, diagnostics, and sometimes macros/documentation. Changing them is often source-compatible Rust, but it can still create unnecessary documentation churn. Apply naming cleanup deliberately, especially in mature public APIs.

## Practical Guidance

- Follow `UpperCamelCase` for type parameters.
- Prefer conventional single letters when the role is obvious: `T`, `E`, `K`, `V`, `F`.
- Use concise descriptive names when multiple semantic roles would otherwise be hard to decode.
- Avoid redundant `Type` suffixes unless they genuinely disambiguate a domain term.
- Put complex bounds in `where` clauses for readability; do not encode the bounds into the parameter name.
- Treat letter meanings as local conventions, not reserved language meanings.

## See Also

- [name-lifetime-short](./name-lifetime-short.md) - Lifetime parameter naming
- [name-types-camel](./name-types-camel.md) - Type-level casing
- [type-generic-bounds](./type-generic-bounds.md) - Trait bounds
