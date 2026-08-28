# macro-export-crate-path

> Use `#[macro_export]` when a `macro_rules!` macro is part of the public crate API

## Why It Matters

A plain `macro_rules!` definition has textual scope and crate-local visibility. `#[macro_export]` gives the macro public path-based scope at the **crate root**, regardless of which module contains the definition. Downstream Rust 2018+ code can then call `mycrate::my_macro!(...)` directly or import it with `use mycrate::my_macro;`.

That is different from the older `#[macro_use] extern crate ...` mechanism, which bulk-imports macros into a macro-use prelude. Prefer explicit path-based use in modern code.

## Bad: Implicit Macro Import

This compiles, but the caller gets the macro through implicit textual/macro-use scope rather than an explicit path:

<!-- rust-check: compile -->
```rust
#[macro_use]
mod legacy_macros {
    macro_rules! greet {
        ($name:expr) => {
            println!("hello, {}", $name);
        };
    }
}

fn main() {
    greet!("world");
}
```

The cross-crate legacy form is the same idea:

```text
#[macro_use]
extern crate mylib;

greet!("world");
```

Use it only when compatibility or an intentionally broad macro import requires it.

## Good: Export at the Crate Root

`#[macro_export]` already creates the public root path. Do **not** redundantly write `pub use greet;` in that same root scope.

<!-- rust-check: compile -->
```rust
#[doc(hidden)]
pub mod __private {
    pub fn print_greeting(name: &str) {
        println!("hello, {name}");
    }
}

#[macro_export]
macro_rules! greet {
    ($name:expr) => {
        $crate::__private::print_greeting($name)
    };
}

mod consumer {
    // A downstream crate would use `use mylib::greet;` here.
    use crate::greet;

    pub fn run() {
        greet!("world");
    }
}

fn main() {
    consumer::run();
}
```

A downstream crate may equivalently invoke the macro without importing it:

```text
mylib::greet!("world");
```

## Re-export Under Another Module Path

`#[macro_export]` always creates the root export. If a secondary module path is useful, re-export the root macro **from that module**. An alias avoids implying that the original definition lived there.

<!-- rust-check: compile -->
```rust
#[macro_export]
macro_rules! greet_impl {
    ($name:expr) => {
        println!("hello, {}", $name);
    };
}

pub mod macros {
    pub use crate::greet_impl as greet;
}

fn main() {
    crate::macros::greet!("world");
}
```

The root path `crate::greet_impl!` still exists because `#[macro_export]` put it there. If exposing only a module-scoped macro path is important, a plain `macro_rules!` definition plus an appropriate declaration re-export may fit better than `#[macro_export]`.

## Helpers Used by Exported Macros

Use `$crate::...` when an exported macro refers back to items or helper macros in its defining crate. `$crate` does not bypass normal visibility: a non-macro helper that must be reached from a downstream expansion still needs sufficient public visibility. `#[doc(hidden)] pub` is a common way to expose implementation support without advertising it as normal API.

Avoid `#[macro_export(local_inner_macros)]` in new code. It exists mainly for migrating older macros that predate `$crate`-qualified helper calls.

## Key Points

- `#[macro_export]` exports a `macro_rules!` macro from the crate root.
- Rust 2018+ callers can use normal path imports or qualified macro paths.
- Do not re-import the same exported macro name back into the crate root; the root path already exists.
- Re-export from another module only when you intentionally want an additional path.
- Use `$crate::...` for defining-crate helper paths inside exported declarative macros.
- `$crate` does not change item visibility.

## See Also

- [macro-rules-hygiene](macro-rules-hygiene.md) - mixed-site hygiene and `$crate`
- [macro-private-helpers](macro-private-helpers.md) - helpers used by exported macros
- [proj-workspace-deps](proj-workspace-deps.md) - workspace dependency inheritance
