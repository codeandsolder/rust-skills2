# proj-feature-additive

> Design Cargo features to be additive whenever feature unification can combine them

## Why It Matters

Cargo may unify features requested for the same dependency package, taking their union. A feature therefore should not normally mean “turn some other capability off”: another dependency can enable both features even when one direct consumer expected only one of them.

Treat features as capabilities that can coexist. This is especially important for library crates. Mutually exclusive modes sometimes exist for unavoidable backend or platform reasons, but they are a constraint to detect and document rather than a model Cargo enforces for you.

## Bad

```toml
[features]
# Enabling this feature removes the default std implementation.
no_std = []
```

A downstream dependency that enables `no_std` can have that feature unified with another consumer's feature set. Negative feature names are also difficult to compose: Cargo features are good at adding configuration, not subtracting it.

## Good

```toml
[features]
# The implementation is capable of no_std without default features;
# enabling `std` adds standard-library integration.
default = ["std"]
std = []

serde = ["dep:serde"]

[dependencies]
serde = { version = "1", optional = true }
```

For a library that uses allocation in its no-std configuration, the crate root can look like this:

```text
#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(not(feature = "std"))]
extern crate alloc;

#[cfg(feature = "std")]
pub type Buffer<T> = std::vec::Vec<T>;

#[cfg(not(feature = "std"))]
pub type Buffer<T> = alloc::vec::Vec<T>;

pub fn empty_buffer<T>() -> Buffer<T> {
    Buffer::new()
}
```

That is a crate-root/library example, not an ordinary generated binary snippet. This repository therefore verifies the same source in `checks/fixtures/feature-additive` as a real library under both intended configurations:

```bash
cargo check --manifest-path checks/fixtures/feature-additive/Cargo.toml --lib
cargo check --manifest-path checks/fixtures/feature-additive/Cargo.toml --lib --no-default-features
```

Testing both configurations matters: compiling only the default `std` branch does not prove the no-std branch is coherent.

## Optional Dependencies

Use `dep:name` when you want a named feature to control an optional dependency without also exposing the dependency name as an implicit public feature:

```toml
[features]
json = ["dep:serde_json"]

[dependencies]
serde_json = { version = "1", optional = true }
```

## Mutually Exclusive Features

Prefer an additive design when possible: select a backend with a runtime/configuration value, put incompatible implementations in separate crates, or expose separate constructors/types.

When two features genuinely cannot coexist, fail loudly instead of silently picking one based on `cfg` order:

```rust
#[cfg(all(feature = "backend_a", feature = "backend_b"))]
compile_error!("features `backend_a` and `backend_b` cannot be enabled together");

fn main() {}
```

That check documents the limitation, but it does not stop dependency feature unification from producing the conflicting combination. Consumers must still coordinate the feature set.

## Avoid Feature-Dependent Semantic Rewrites

Adding optional APIs, trait impls, dependencies, or integrations is usually composable. Changing the meaning of an existing public item when a feature is enabled is much harder to reason about, even if both configurations compile. Prefer separate items or explicit configuration when callers may observe meaningfully different semantics.

## See Also

- [api-serde-optional](./api-serde-optional.md) - gate serialization integration behind a feature
- [proj-workspace-deps](./proj-workspace-deps.md) - workspace dependency inheritance
- [lint-cfg-check](./lint-cfg-check.md) - catch feature-gate typos
