# proj-prelude-module

> Offer a small opt-in `prelude` only when callers repeatedly need the same coherent set of imports.

## Why It Matters

A crate prelude is a conventional module whose contents users import explicitly with `use my_crate::prelude::*`. Unlike Rust's language/standard preludes, a library-defined prelude is **not imported automatically**.

A good prelude can reduce repetitive imports for APIs built around extension traits or a tightly related group of core types. A bad prelude hides where names come from, increases collision risk, and creates another public surface that must remain coherent over time.

Do not create a prelude merely because other crates have one. Explicit imports are often clearer.

## Bad: A Grab-Bag Prelude

<!-- rust-check: compile -->
```rust
pub struct Client;
pub struct Config;
pub struct Error;
pub struct RareAdminTool;

pub mod prelude {
    // BAD: unrelated/rare items make glob imports unpredictable.
    pub use crate::{Client, Config, Error, RareAdminTool};

    // BAD: re-exporting a whole large namespace greatly increases collision risk.
    pub use std::collections::*;
}

fn consumer() {
    use crate::prelude::*;

    let _ = Client;
    let _ = RareAdminTool;
    let _map: HashMap<String, String> = HashMap::new();
}
```

This compiles. The problem is API design: the glob imports far more names than most callers need and makes future additions more likely to collide with downstream names.

## Good: Small, Coherent, Opt-In

<!-- rust-check: compile -->
```rust
pub struct Client;
pub struct Config;

pub trait Execute {
    fn execute(&self) -> &'static str;
}

impl Execute for Client {
    fn execute(&self) -> &'static str {
        "ok"
    }
}

pub mod prelude {
    pub use crate::{Client, Config, Execute};
}

fn consumer() {
    use crate::prelude::*;

    let client = Client;
    let _config = Config;
    assert_eq!(client.execute(), "ok");
}
```

This prelude has a reason to exist: callers commonly need the main types plus the trait that enables their methods.

## Explicit Imports Must Remain First-Class

A prelude is convenience, not a requirement.

<!-- rust-check: compile -->
```rust
pub struct Client;
pub struct Config;

pub mod prelude {
    pub use crate::{Client, Config};
}

fn explicit_style() {
    use crate::{Client, Config};
    let _ = (Client, Config);
}

fn prelude_style() {
    use crate::prelude::*;
    let _ = (Client, Config);
}
```

Documentation should still use explicit imports when the origin of a name matters to understanding the example.

## What Belongs in a Prelude?

Good candidates are names that are both:

- needed by a large fraction of normal users, and
- naturally used together.

Common examples include extension traits whose methods otherwise appear to be missing, core context/handle types, and a few ubiquitous aliases.

Usually leave out:

- rare subsystems,
- implementation helpers,
- broad re-exports of another crate,
- generic names such as `Error`, `Result`, `Future`, or `Context` unless the crate's ecosystem strongly expects them,
- items callers only need in specialized modules.

There is no fixed item-count threshold. Judge by actual call sites and namespace clarity.

## Prelude Changes Have Compatibility Costs

A prelude is public API. Removing or renaming an exported item is directly breaking for callers that import it.

Even **adding** a name can cause downstream glob-import ambiguity when a caller already obtains the same identifier from another glob or local import. This is one reason to keep preludes deliberately small and stable.

Do not treat a prelude as a dumping ground where every new public type is automatically added.

## Feature-Gated Items

Feature-gated items can be re-exported from a prelude when that is the ergonomic API, but gate the re-export with the same feature so the prelude remains valid in every supported feature combination.

<!-- rust-check: compile -->
```rust
pub struct Client;

#[cfg(feature = "experimental")]
pub struct ExperimentalClient;

pub mod prelude {
    pub use crate::Client;

    #[cfg(feature = "experimental")]
    pub use crate::ExperimentalClient;
}
```

Whether feature-specific names belong in the common prelude is an API-design question, not a blanket prohibition.

## Tiered Convenience Modules

If a crate has a genuinely common core and a large optional convenience surface, separate modules can be clearer than one enormous glob.

<!-- rust-check: compile -->
```rust
pub struct Client;
pub struct Config;
pub struct AdvancedPlanner;

pub mod prelude {
    pub use crate::{Client, Config};
}

pub mod advanced_prelude {
    pub use crate::prelude::*;
    pub use crate::AdvancedPlanner;
}
```

Name such modules by semantics rather than inventing `full_prelude` solely to re-export everything.

## Document the Contract

Prelude module docs should say that it is optional and summarize the categories it exports. Users should not need to inspect source to discover why a trait method only appears after a glob import.

When examples rely on prelude-provided traits, consider naming those traits in prose even if the code uses the glob.

## Decision Guide

| Situation | Recommendation |
|---|---|
| A few obvious explicit imports | Prefer explicit imports |
| Many call sites repeat the same coherent imports | Consider a small prelude |
| Extension traits are essential to normal use | Prelude can improve discoverability |
| Prelude would mostly contain rare modules | Skip it |
| New item is public | Do not automatically add it to the prelude |
| Specialized feature/subsystem | Prefer its own module/import path unless common usage justifies inclusion |

## See Also

- [proj-pub-use-reexport](./proj-pub-use-reexport.md) - Curating public paths
- [api-extension-trait](./api-extension-trait.md) - Extension traits
- [doc-module-inner](./doc-module-inner.md) - Module documentation
