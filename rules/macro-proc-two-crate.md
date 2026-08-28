# macro-proc-two-crate

> Put procedural macros in a dedicated `proc-macro = true` crate and re-export them from the ordinary library facade

## Why It Matters

A procedural macro must live in a crate whose library target has `proc-macro = true`. Such a crate exports procedural macros, not an ordinary public library API. If one product needs both a normal Rust API and derives/attributes/function-like procedural macros, the usual structure is therefore two crates:

- `mycrate` — the ordinary library and public facade;
- `mycrate-derive` or `mycrate-macros` — the `proc-macro = true` implementation crate.

The facade can re-export the macros so users normally depend on only `mycrate`.

Do not confuse that packaging pattern with generated-code hygiene. Procedural macros are **unhygienic**: emitted paths behave like source written at the invocation site. There is no procedural-macro equivalent of declarative `$crate`, so generated references back to the facade need an explicit path strategy.

## Bad: Trying to Export Ordinary API from a Proc-Macro Crate

This intentionally requires a real proc-macro crate target. The dedicated fixture checks that the crate fails for the specific proc-macro export restriction rather than merely accepting any compiler failure:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
use proc_macro::TokenStream;

#[proc_macro_derive(Greet)]
pub fn derive_greet(_input: TokenStream) -> TokenStream {
    TokenStream::new()
}

pub trait Greet {
    fn greet(&self) -> String;
}
```

Put the trait in the ordinary library crate and the derive implementation in the proc-macro crate instead.

## Good: Facade + Proc-Macro Crate

```text
my-workspace/
├── Cargo.toml
├── mycrate/
│   ├── Cargo.toml
│   └── src/lib.rs
└── mycrate-derive/
    ├── Cargo.toml
    └── src/lib.rs
```

### Workspace manifest

```toml
[workspace]
members = ["mycrate", "mycrate-derive"]
resolver = "3"

[workspace.dependencies]
mycrate-derive = { path = "mycrate-derive", version = "0.1" }
syn = { version = "2", features = ["derive"] }
quote = "1"
proc-macro2 = "1"
```

### Proc-macro crate

```toml
# mycrate-derive/Cargo.toml
[package]
name = "mycrate-derive"
version = "0.1.0"
edition = "2024"

[lib]
proc-macro = true

[dependencies]
syn.workspace = true
quote.workspace = true
proc-macro2.workspace = true
```

### Facade crate

```toml
# mycrate/Cargo.toml
[package]
name = "mycrate"
version = "0.1.0"
edition = "2024"

[dependencies]
mycrate-derive.workspace = true
```

The facade may expose a trait and a derive macro with the same spelling because they occupy different namespaces:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
// mycrate/src/lib.rs
pub use mycrate_derive::Greet;

pub trait Greet {
    fn greet(&self) -> String;
}

#[doc(hidden)]
pub mod __private {
    pub fn format_greeting(name: &str) -> String {
        format!("hello, {name}")
    }
}
```

A consumer can then depend on the facade and use both APIs:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
use mycrate::Greet;

#[derive(mycrate::Greet)]
struct Robot;

fn main() {
    let robot = Robot;
    println!("{}", robot.greet());
}
```

The repository fixture exercises the same public shape through a dependency deliberately renamed to `api`, which also verifies the generated-path strategy below.

## Generated Paths: Do Not Blindly Hardcode `::mycrate`

A derive implementation often needs to emit a path back to the facade trait or helper API. This is tempting:

```text
impl ::mycrate::Greet for Robot { ... }
```

but it fails if the downstream manifest renames the dependency:

```toml
[dependencies]
api = { package = "mycrate", version = "0.1" }
```

The Rust path is then `api`, not `mycrate`.

Procedural macros have no `$crate` token that resolves to the defining facade. Choose one of these strategies deliberately:

1. **Emit only language/std paths** when the expansion does not actually need the facade.
2. **Accept a crate path from the user** when configuration is already part of the macro API, for example `#[greet(crate = api)]`.
3. **Resolve the Cargo dependency name** in the proc-macro crate. The `proc-macro-crate` crate exists specifically for this problem and distinguishes the current crate from a renamed dependency.

A typical resolver shape is:

<!-- rust-check: fixture(proc-macro-contracts) -->
```rust
use proc_macro2::Span;
use proc_macro_crate::{crate_name, FoundCrate};
use quote::quote;
use syn::Ident;

fn facade_path() -> proc_macro2::TokenStream {
    match crate_name("mycrate").expect("mycrate must be present") {
        FoundCrate::Itself => quote!(crate),
        FoundCrate::Name(name) => {
            let ident = Ident::new(&name, Span::call_site());
            quote!(::#ident)
        }
    }
}
```

Then splice that resolved path into the generated implementation rather than assuming the package name is also the downstream Rust identifier.

`proc-macro-crate` has edge cases of its own, so a user-specified override can still be useful for unusual manifests.

## Helper Visibility

If generated code calls `mycrate::__private::helper`, that helper is part of what downstream compilation must be able to reach. `#[doc(hidden)] pub` can keep it out of normal docs, but it is still public and is part of the compatibility surface used by macro expansions.

Keep the macro implementation crate as an implementation detail when practical: users should normally depend on the facade, and the facade should re-export the supported procedural macros.

## Key Points

- Procedural macros require a `proc-macro = true` crate.
- Put normal traits/types/functions in an ordinary library crate and commonly re-export macros from that facade.
- Procedural macro output is unhygienic; use explicit, collision-resistant, appropriately qualified paths.
- There is no procedural `$crate` equivalent for finding the facade crate.
- Hardcoding `::mycrate` breaks when downstream users rename the dependency.
- Use a path override or a crate-name resolver such as `proc-macro-crate` when generated code must refer back to the facade.
- Helpers reached by generated downstream code need real visibility even if hidden from rustdoc.

## See Also

- [macro-proc-syn-quote](macro-proc-syn-quote.md) - building proc macros with syn and quote
- [macro-private-helpers](macro-private-helpers.md) - helper APIs used by expansions
- [proj-workspace-deps](proj-workspace-deps.md) - workspace dependency inheritance
- [err-thiserror-lib](err-thiserror-lib.md) - a facade/proc-macro ecosystem example
