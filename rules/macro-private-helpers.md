# macro-private-helpers

> Route exported-macro support items through a clearly marked `#[doc(hidden)]` module when call-site visibility requires them to be public

## Why It Matters

An exported declarative macro expands in another crate. Any helper item referenced by the expansion must therefore be reachable from that call site. A common pattern is a public, documentation-hidden module such as `__private` that exposes only the support surface generated code needs.

`#[doc(hidden)]` is **not** privacy and is **not** a semver exemption. The items remain publicly reachable Rust API. The convention reduces documentation clutter and signals “implementation detail,” but downstream code can still name the path. Keep the surface small and coordinate changes with the macros that generate references to it.

## Bad: Scatter Helpers Across the Crate Root

```rust
pub fn __format_value(value: &dyn std::fmt::Debug) -> String {
    format!("{value:?}")
}

#[macro_export]
macro_rules! debug_print {
    ($value:expr) => {
        println!("{}", $crate::__format_value(&$value));
    };
}

fn main() {
    debug_print!(42);
}
```

The helper is callable by downstream code and appears as an ordinary top-level API item even though its purpose is macro support.

## Good: Concentrate the Required Public Support Surface

```rust
mod helpers {
    pub fn format_value(value: &dyn std::fmt::Debug) -> String {
        format!("{value:?}")
    }
}

#[doc(hidden)]
pub mod __private {
    pub use crate::helpers::format_value;
}

#[macro_export]
macro_rules! debug_print {
    ($value:expr) => {
        println!("{}", $crate::__private::format_value(&$value));
    };
}

fn main() {
    debug_print!(42);
}
```

Inside `macro_rules!`, use `$crate` for helpers in the defining crate so the expansion does not depend on which name the caller imported the crate under.

## Procedural-Macro Facades

A facade crate and a derive crate are normally separate Cargo targets. The facade may expose a hidden runtime/support path used by generated code:

```text
// facade/src/lib.rs
#[doc(hidden)]
pub mod __private {
    pub use crate::runtime::{describe_fields, Describe};
}

pub use facade_derive::Describe;
```

Generated code can then target the facade's support surface:

```text
impl ::facade::__private::Describe for MyStruct {
    fn describe(&self) -> String {
        ::facade::__private::describe_fields(&[])
    }
}
```

That sketch is intentionally shown as multi-crate source rather than a standalone Rust example. A real derive implementation also needs to handle dependency renaming; do not blindly hardcode `::facade` unless the public contract requires that exact crate name. See the dedicated proc-macro rule for rename-aware generated paths.

## Semver Consequences

Hidden public support APIs are still observable by downstream compilation. Treat changes deliberately:

- generated code from the same release may depend on an exact helper path or signature;
- old macro expansions can appear in downstream incremental/build artifacts;
- users can call hidden public items even if documentation discourages it.

If a helper can remain private because the macro does not reference it from downstream code, keep it private. `__private` is for the minimum support surface that truly must cross the crate boundary.

## Key Points

- `#[doc(hidden)]` hides rendered documentation; it does not change Rust visibility.
- `$crate::__private::...` is the robust path form for declarative macros referring back to their defining crate.
- Keep the hidden public module narrow.
- For procedural macros, coordinate the facade/runtime API with generated paths and dependency-renaming behavior.

## See Also

- [macro-rules-hygiene](./macro-rules-hygiene.md) - `$crate` and mixed-site hygiene
- [macro-proc-two-crate](./macro-proc-two-crate.md) - facade/proc-macro crate separation and generated paths
- [doc-all-public](./doc-all-public.md) - documenting the intended public API
