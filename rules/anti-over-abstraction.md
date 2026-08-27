# anti-over-abstraction

> Introduce generics and traits when they express a stable semantic boundary; do not generalize code solely for hypothetical flexibility

## Why It Matters

Rust gives several forms of abstraction—generic type parameters, traits, trait objects, associated types, enums, macros, and ordinary functions. Each can make code clearer when it captures a real relationship, and each can make code harder to understand when it exists only because “we might need this later.”

The costs are not one-dimensional:

- generics can increase compile time and code generation through monomorphization;
- static dispatch can also enable inlining and specialization-like optimization opportunities;
- trait objects reduce monomorphization but add dynamic dispatch and object-safety constraints;
- public abstractions become compatibility commitments;
- private abstractions can simplify testing or separate subsystems even with one current implementation.

There is no magic implementation count at which abstraction suddenly becomes correct.

## Start Concrete When the Domain Is Concrete

```rust
fn add_i32(left: i32, right: i32) -> i32 {
    left + right
}

fn main() {
    assert_eq!(add_i32(2, 3), 5);
}
```

If the program only adds `i32` values, this function is honest and easy to read. Generalizing it to unrelated input/output conversion types adds complexity without a demonstrated need.

## Generalize When the Shared Operation Is Real

```rust
use std::ops::Add;

fn add<T>(left: T, right: T) -> T
where
    T: Add<Output = T>,
{
    left + right
}

fn main() {
    assert_eq!(add(2_i32, 3_i32), 5);
    assert_eq!(add(1.5_f64, 2.0_f64), 3.5);
}
```

This generic version earns its abstraction if callers genuinely need the same operation over multiple compatible types.

## A Trait Can Define an Architectural Boundary

A trait is not automatically over-engineering merely because there is currently one implementation. It may define a plugin boundary, isolate external infrastructure, support tests, or express behavior consumed by generic algorithms.

```rust
use std::collections::HashMap;

trait Storage {
    fn save(&mut self, key: &str, value: Vec<u8>);
    fn load(&self, key: &str) -> Option<&[u8]>;
}

#[derive(Default)]
struct MemoryStorage {
    values: HashMap<String, Vec<u8>>,
}

impl Storage for MemoryStorage {
    fn save(&mut self, key: &str, value: Vec<u8>) {
        self.values.insert(key.to_owned(), value);
    }

    fn load(&self, key: &str) -> Option<&[u8]> {
        self.values.get(key).map(Vec::as_slice)
    }
}

fn round_trip(storage: &mut impl Storage) -> bool {
    storage.save("answer", vec![42]);
    storage.load("answer") == Some(&[42][..])
}

fn main() {
    let mut storage = MemoryStorage::default();
    assert!(round_trip(&mut storage));
}
```

The question is whether `Storage` represents a useful boundary, not whether a second implementation already exists in the repository.

## Do Not Use a “Rule of Three” as a Gate

Waiting for repeated concrete cases can prevent premature abstraction, but “exactly three implementations before a trait” is folklore, not a Rust rule.

Abstract earlier when the boundary is part of the design:

- a public extension trait;
- a backend interface intentionally supplied by callers;
- a test seam around nondeterministic/external behavior;
- a generic algorithm whose real inputs already vary.

Abstract later—or never—when implementations only look superficially similar and their semantics are still diverging.

## Marker Traits Can Be Meaningful

A trait with no methods is not inherently suspicious. Rust itself uses marker traits such as `Send` and `Sync` to express semantic properties that other code relies on.

A private marker can also be useful for sealing or classification:

```rust
mod sealed {
    pub trait Sealed {}
}

trait WireFormat: sealed::Sealed {}

struct Json;
struct Binary;

impl sealed::Sealed for Json {}
impl sealed::Sealed for Binary {}
impl WireFormat for Json {}
impl WireFormat for Binary {}

fn accepts_format<T: WireFormat>(_format: T) {}

fn main() {
    accepts_format(Json);
    accepts_format(Binary);
}
```

A marker trait should communicate a real invariant or category. A pile of empty traits invented only to mirror nouns in a design document is different.

## Public Generics Are a Compatibility Choice

It is not automatically better to make public APIs generic “for flexibility.” A generic parameter exposes bounds, inference behavior, monomorphization, and future-coherence constraints to callers.

Concrete public types can be more stable and easier to evolve when extension is not intended. Conversely, a generic public API is appropriate when caller-supplied types are a core feature.

Decide intentionally rather than using “public means abstract, private means concrete.”

## Closed Sets Often Prefer Enums

If all variants are known and controlled by the crate, an enum can be clearer than a trait hierarchy:

```rust
#[derive(Debug)]
enum Compression {
    None,
    Fast,
    Dense,
}

impl Compression {
    fn level(&self) -> u8 {
        match self {
            Compression::None => 0,
            Compression::Fast => 1,
            Compression::Dense => 9,
        }
    }
}

fn main() {
    assert_eq!(Compression::Dense.level(), 9);
}
```

Use traits when an open set of implementations or generic behavioral abstraction is useful; use enums when exhaustiveness over a closed set is useful.

## `Deref` Is Not General Method Delegation

`Deref` participates in implicit deref coercions and method lookup. Implement it when your type intentionally behaves like a smart pointer or transparent wrapper to its target—not merely to save a few forwarding methods.

```rust
struct Email(String);

impl Email {
    fn as_str(&self) -> &str {
        &self.0
    }

    fn domain(&self) -> Option<&str> {
        self.0.split_once('@').map(|(_, domain)| domain)
    }
}

fn main() {
    let email = Email("ada@example.com".to_owned());
    assert_eq!(email.as_str(), "ada@example.com");
    assert_eq!(email.domain(), Some("example.com"));
}
```

An `Email: Deref<Target = str>` implementation would expose implicit `&str` coercion everywhere. That may be desirable for a transparent string-like wrapper, but it weakens the wrapper boundary and should be an intentional API decision.

See [anti-deref-overuse](./anti-deref-overuse.md) for the dedicated rule.

## Signs Worth Reviewing, Not Automatic Failures

These patterns deserve a design check rather than an automatic rejection:

| Pattern | Ask |
|---|---|
| trait with one implementation | Is it a meaningful boundary/test seam/extension point? |
| many type parameters | Are the independent roles really necessary and understandable? |
| deep bounds | Is this one abstraction doing too many jobs? |
| marker trait | What invariant/category does it communicate? |
| generic public API | Do callers genuinely supply different types? |
| repeated forwarding methods | Would composition/delegation or transparent `Deref` semantics be clearer? |

## Performance Claims Need Measurement

Do not reject generics because “they make binaries larger” or prefer them because “static dispatch is zero cost” without context. Monomorphization, inlining, branch prediction, code size, and compile time vary with the actual program.

Choose an abstraction for semantics first. Profile/build-measure when performance or binary size is material.

## Practical Guidance

- Start concrete when requirements are concrete and uncertain.
- Generalize when an abstraction captures real shared behavior or a deliberate architectural boundary.
- Do not require two or three implementations before a trait can be justified.
- Treat public generics as API commitments, not free future-proofing.
- Use enums for closed sets and traits/generics for open behavioral sets when appropriate.
- Allow marker traits when they encode a real semantic property.
- Implement `Deref` only when implicit target-like behavior is part of the abstraction.
- Measure compile time, code size, and runtime effects instead of relying on blanket performance claims.

## See Also

- [type-generic-bounds](./type-generic-bounds.md) - Generic bounds
- [api-sealed-trait](./api-sealed-trait.md) - Controlled extension
- [anti-type-erasure](./anti-type-erasure.md) - Static versus dynamic polymorphism
- [anti-deref-overuse](./anti-deref-overuse.md) - `Deref` API semantics
