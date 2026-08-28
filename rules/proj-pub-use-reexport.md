# proj-pub-use-reexport

> Use `pub use` to curate intentional public paths; do not expose internal module layout or dependency types accidentally.

## Why It Matters

A public `use` declaration re-exports a name. It can give callers a stable, ergonomic path even when the item's defining module is private.

That separation is useful: internal modules can reflect implementation structure while the crate root or another public facade presents the API callers are expected to depend on.

But a re-export is still **public API**. Moving, removing, renaming, or changing the meaning of that public path can break downstream code. Re-exporting a dependency's type also makes that dependency type part of your compatibility surface; it does not magically hide the dependency.

## Bad: Internal Module Tree Becomes the API by Accident

<!-- rust-check: compile -->
```rust
pub mod implementation {
    pub mod transport {
        pub mod http {
            pub struct Client;
        }
    }

    pub mod config {
        pub struct Config;
    }
}

fn internal_user() {
    let _client = implementation::transport::http::Client;
    let _config = implementation::config::Config;
}
```

This is valid, but every public ancestor module forms part of the path downstream users can name. Reorganizing `implementation::transport::http` later can therefore break callers that adopted that path.

## Good: Private Organization, Curated Public Paths

<!-- rust-check: compile -->
```rust
mod implementation {
    pub mod transport {
        pub mod http {
            pub struct Client;
        }
    }

    pub mod config {
        pub struct Config;
    }
}

pub use implementation::config::Config;
pub use implementation::transport::http::Client;

fn consumer() {
    let _client = Client;
    let _config = Config;
}
```

The defining modules remain private, but `Client` and `Config` are publicly reachable through the re-export paths.

## Re-Exports Can Cross Private Ancestors

Rust specifically allows a public re-export to provide access to a public item whose canonical module path contains private ancestors.

<!-- rust-check: compile -->
```rust
mod hidden {
    pub mod nested {
        pub struct PublicType;
    }
}

pub use hidden::nested::PublicType;

fn use_public_path() {
    let _ = PublicType;
}
```

This is a useful tool for decoupling file/module layout from the names documented as your crate's API.

## Selective Re-Export Beats `pub use module::*`

<!-- rust-check: compile -->
```rust
mod internal {
    pub struct Client;
    pub struct Config;
    pub struct DebugDump;
    pub fn internal_probe() {}
}

pub use internal::{Client, Config};

fn public_consumer() {
    let _ = (Client, Config);
}
```

Selective lists make API review obvious. A glob re-export can be appropriate for a deliberately facade-like module, but it also means newly added source-module names may silently become public API.

## Renaming on Re-Export

<!-- rust-check: compile -->
```rust
mod v1 {
    pub struct Client;
}

mod v2 {
    pub struct Client;
}

pub use v1::Client as LegacyClient;
pub use v2::Client;

fn consumer() {
    let _new = Client;
    let _old = LegacyClient;
}
```

Aliases are useful for migrations or when two source modules expose colliding names. Remember that both exported names become compatibility commitments while public.

## Re-Exporting Dependency Types Is a Public-Dependency Decision

Sometimes callers really should use the exact dependency type accepted or returned by your API. Re-exporting it can give them one canonical path.

<!-- rust-check: compile -->
```rust
pub use bytes::Bytes;

pub fn encode(text: &str) -> Bytes {
    Bytes::copy_from_slice(text.as_bytes())
}
```

This is convenient, but `bytes::Bytes` is now deliberately visible in your API. Upgrading to a semver-incompatible version or replacing it with another type can be a breaking API change even though callers spelled the type through your crate's re-export.

If the dependency is an implementation detail, prefer your own type/trait boundary instead of re-exporting it merely to save callers a dependency declaration.

Also do not assume re-exporting means consumers will **never** need a direct dependency. They may need dependency-specific macros, traits, feature flags, companion types, or APIs you do not re-export.

## Feature-Gated Re-Exports

If an item only exists behind a feature, gate the public path consistently.

<!-- rust-check: compile -->
```rust
mod core_api {
    pub struct Client;
}

#[cfg(feature = "async-client")]
mod async_api {
    pub struct AsyncClient;
}

pub use core_api::Client;

#[cfg(feature = "async-client")]
pub use async_api::AsyncClient;
```

Document which feature controls the path. A caller should not discover feature requirements only from an unresolved import.

## Facade Crates Are a Deliberate Special Case

Some crates intentionally exist mostly to re-export APIs from several dependencies. In that design, broad re-exports may be the product rather than leakage.

The same compatibility consequence still applies: the facade owns the public paths it exposes and must consider upstream dependency changes as changes to its own API.

## Re-Export vs Type Alias vs Wrapper

Use the mechanism that matches the compatibility goal:

- **`pub use dep::Type`** — expose the exact same type and its identity.
- **`pub type Alias = dep::Type`** — provide another name for the exact same type; dependency identity still leaks.
- **newtype/wrapper** — create your own type identity and conversion boundary; more work, more encapsulation.
- **trait/interface owned by your crate** — useful when callers should program to behavior rather than a concrete dependency type.

## Public Paths Are Part of SemVer

Before changing module visibility or re-exports, ask which paths users can currently name. Making a formerly public module private is breaking unless every public path callers relied on is intentionally preserved and behavior/type identity remains compatible.

Conversely, keeping implementation modules private from the start preserves more freedom to reorganize them behind stable re-export paths.

## Decision Guide

| Goal | Typical approach |
|---|---|
| Hide internal module nesting | Private modules + selective root re-exports |
| Expose a small curated facade | Explicit `pub use` list |
| Preserve two names during migration | Re-export with alias |
| Exact dependency type is intentionally public | Re-export it and treat dependency as public API |
| Dependency should remain swappable | Own a wrapper/trait boundary |
| Crate is intentionally a facade | Broader re-exports can be appropriate |

## See Also

- [proj-prelude-module](./proj-prelude-module.md) - Optional convenience imports
- [proj-pub-crate-internal](./proj-pub-crate-internal.md) - Internal visibility
- [api-non-exhaustive](./api-non-exhaustive.md) - Future-proof public types
