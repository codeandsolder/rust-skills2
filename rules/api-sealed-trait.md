# api-sealed-trait

> Seal a public trait when downstream crates should be able to use it but not implement it

## Why It Matters

A public trait is normally an extension point: downstream crates can implement it for their own types when coherence allows. That is useful when third-party implementations are part of the design, but it also means adding a new required method is a breaking change for those implementations.

A sealed trait deliberately closes that extension point. Downstream code can still name the public trait, call its methods, use it in bounds, and work with your implementations, but it cannot add new implementations. This gives the defining crate more freedom to evolve the trait's implementation requirements.

Sealing does not make implementations correct by itself. It only ensures that the defining crate controls the set of implementations.

## Good: Private Supertrait Pattern

```rust
mod sealed {
    pub trait Sealed {}
}

pub trait Backend: sealed::Sealed {
    fn name(&self) -> &'static str;
}

pub struct Local;
pub struct Remote;

impl sealed::Sealed for Local {}
impl sealed::Sealed for Remote {}

impl Backend for Local {
    fn name(&self) -> &'static str {
        "local"
    }
}

impl Backend for Remote {
    fn name(&self) -> &'static str {
        "remote"
    }
}

fn describe(backend: &impl Backend) -> &'static str {
    backend.name()
}

fn main() {
    assert_eq!(describe(&Local), "local");
    assert_eq!(describe(&Remote), "remote");
}
```

The `sealed::Sealed` trait is public only inside a private module. The public `Backend` trait can expose it as a supertrait, but downstream crates cannot name the private module in an impl and therefore cannot satisfy the supertrait requirement for their own types.

## Why This Helps API Evolution

Suppose a later release needs another required method:

```rust
mod sealed {
    pub trait Sealed {}
}

pub trait Format: sealed::Sealed {
    fn compact(&self) -> String;
    fn pretty(&self) -> String;
}

pub struct Json;
impl sealed::Sealed for Json {}

impl Format for Json {
    fn compact(&self) -> String {
        "{}".to_owned()
    }

    fn pretty(&self) -> String {
        "{\n}".to_owned()
    }
}

fn main() {
    assert_eq!(Json.pretty(), "{\n}");
}
```

Because downstream crates could not implement `Format`, adding a required method does not invalidate downstream trait impls. The defining crate still has to update all of its own implementations.

Sealing does **not** make arbitrary trait changes non-breaking. Removing a public method, changing a callable signature, changing semantics, or otherwise breaking downstream uses can still be a compatibility break.

## Open Traits Are Often the Right Choice

Do not seal a trait merely because you own it. Leave it open when third-party implementations are an intended capability.

```rust
pub trait Renderer {
    fn render(&self, input: &str) -> String;
}

struct PlainText;

impl Renderer for PlainText {
    fn render(&self, input: &str) -> String {
        input.to_owned()
    }
}

fn main() {
    let renderer = PlainText;
    assert_eq!(renderer.render("hello"), "hello");
}
```

An open trait is appropriate for plugins, adapters, user-defined backends, mocks, and other genuine extension points. Once users depend on being able to implement a trait, sealing it later is itself a breaking API change.

## Sealing for Safety or Invariants

A sealed trait can be useful when implementations participate in an invariant that downstream code cannot be trusted or expected to uphold. The safety argument must still live in the actual implementation and API design; the seal only lets the crate author audit the complete implementation set.

```rust
mod sealed {
    pub trait Sealed {}
}

pub trait TrustedLength: sealed::Sealed {
    fn trusted_len(&self) -> usize;
}

pub struct Packet(Vec<u8>);
impl sealed::Sealed for Packet {}

impl TrustedLength for Packet {
    fn trusted_len(&self) -> usize {
        self.0.len()
    }
}

fn main() {
    let packet = Packet(vec![1, 2, 3]);
    assert_eq!(packet.trusted_len(), 3);
}
```

If unsafe code relies on such a trait, document the invariant explicitly and ensure every in-crate implementation satisfies it. Sealing is not a substitute for that proof.

## Document the Restriction

A sealed trait looks like an ordinary public trait at first glance. Document that downstream implementations are intentionally unsupported so users do not design around an extension point that does not exist.

## Practical Guidance

- Seal a trait when downstream crates should consume it but not implement it.
- Use a private-module supertrait as the conventional stable pattern.
- Treat sealing as an API design decision: it trades extensibility for implementation control and some evolution freedom.
- Do not claim sealing makes every future trait change non-breaking.
- Do not claim sealing guarantees correctness; it only limits who can implement the trait.
- Keep traits open when third-party implementations are part of the intended ecosystem.

## See Also

- [api-do-not-recommend](./api-do-not-recommend.md) - Diagnostic control for impls
- [api-non-exhaustive](./api-non-exhaustive.md) - Reserving evolution space for enums and structs
- [api-extension-trait](./api-extension-trait.md) - Adding methods to foreign types
- [api-typestate](./api-typestate.md) - Compile-time state guarantees
