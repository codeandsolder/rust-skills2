# api-serde-optional

> Make serde optional in general-purpose libraries when serialization is not part of the core API

## Why It Matters

A public library should not force every downstream build to enable serialization support when many users do not need it. An optional dependency plus a feature lets consumers choose serde integration while keeping the core API usable without serde.

This is a design choice, not a universal rule. If serialization is fundamental to the crate's purpose or public types, making serde required can be simpler and more honest.

## Bad

For a general-purpose library whose core functionality does not require serialization:

```toml
[dependencies]
serde = { version = "1", features = ["derive"] }
```

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub name: String,
    pub value: i32,
}
```

Every build now includes serde as a normal dependency of the library, even when the consumer never serializes `Config`.

## Good

Put the dependency configuration in `Cargo.toml`:

```toml
[dependencies]
serde = { version = "1", features = ["derive"], optional = true }

[features]
default = []
serde = ["dep:serde"]
```

Then gate only the serde-specific implementations in Rust:

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Config {
    pub name: String,
    pub value: i32,
}

let config = Config {
    name: "demo".into(),
    value: 7,
};
assert_eq!(config.value, 7);
```

A downstream user opts in with:

```toml
[dependencies]
my_crate = { version = "1", features = ["serde"] }
```

Using `dep:serde` keeps the dependency name from implicitly becoming a separate public feature.

## Keep Feature-Off Builds Healthy

The crate should compile and test both without and with the feature:

```bash
cargo test
cargo test --features serde
cargo test --all-features
```

For crates with several interacting optional features, add CI coverage for combinations that matter instead of assuming `--all-features` catches feature-isolation mistakes.

## Serde-Specific Attributes

Attributes that only exist when serde is enabled should be gated together with the derive or otherwise arranged so the feature-off build remains valid:

```rust
#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(rename_all = "snake_case"))]
pub enum Status {
    Pending,
    InProgress,
    Complete,
}
```

## Optional Serialization for Validated Newtypes

The same feature boundary applies when a helper macro supplies serde implementations. Enable the macro crate's serde support only under your crate's serde feature, and test that deserialization preserves validation invariants.

For example, a crate can forward its feature to an optional dependency:

```toml
[dependencies]
nutype = { version = "0.7", optional = true }
serde = { version = "1", features = ["derive"], optional = true }

[features]
validated-types = ["dep:nutype"]
serde = ["dep:serde", "nutype?/serde"]
```

The exact feature names depend on the dependency; verify them against the version your crate uses rather than copying feature wiring blindly.

## When Serde Should Be Required

Making serde non-optional is reasonable when, for example:

- the crate is itself a serialization/data-format library,
- nearly every public operation consumes or produces serialized data,
- serde traits are intentionally part of the core public API contract,
- an optional feature would create misleading or poorly tested API variants.

Optional dependencies reduce unnecessary coupling only when the feature-off API remains useful.

## Documentation

Document feature names and what they add to public types. If docs.rs is configured to build all features, make it clear that serde impls shown there may require enabling the feature in downstream Cargo manifests.

## See Also

- [api-nutype-validated](./api-nutype-validated.md) - Validated newtypes
- [proj-features-additive](./proj-feature-additive.md) - Feature design
- [api-common-traits](./api-common-traits.md) - Public trait implementations
