# lint-dylint-custom

> Use Dylint for project-specific custom lints without forking clippy

**Rule**: `lint-dylint-custom`

## Why It Matters

Clippy is comprehensive, but projects occasionally need lints that are too specific, experimental, or domain-specific for inclusion in clippy. Dylint provides a framework for authoring and running custom lint libraries without forking clippy or modifying the toolchain.

## When to Use Custom Lints

- Enforcing project-specific API usage patterns
- Banning certain crate imports or function calls
- Custom naming conventions beyond what clippy offers
- Migration helpers for internal deprecations
- Experimental lints before proposing to clippy

## Dylint (Recommended)

[Dylint](https://github.com/trailofbits/dylint) v2.1.3 is a production-ready linting framework by Trail of Bits.

### Installation

```bash
cargo install dylint --version ">=2.1.3"
```

### Project Structure

```text
my-project/
├── Cargo.toml
├── lint-libraries/
│   └── my-custom-lints/
│       ├── Cargo.toml
│       └── src/
│           └── lib.rs
└── src/
    └── main.rs
```

### Custom Lint Example

```rust
// lint-libraries/my-custom-lints/src/lib.rs
#![feature(rustc_private)]
#![deny(unsafe_code)]

dylint_linting::dylint_lint!(
    name = "disallowed_crate",
    level = "deny",
    description = "Denies usage of specified dependencies",
);

declare_lint! {
    /// Disallows importing a specific crate.
    DISALLOWED_CRATE,
    Deny,
    "usage of a disallowed crate",
}

impl<'tcx> LateLintPass<'tcx> for DisallowedCrate {
    fn check_crate(&mut self, cx: &LateContext<'tcx>) {
        if cx.tcx.crate_name(LOCAL_CRATE) == sym::regex {
            cx.sess().struct_span_err(
                Span::default(),
                "use of `regex` crate is not allowed; use `regex-lite` instead",
            )
            .emit();
        }
    }
}
```

### Running

```bash
# Run custom lint library
cargo dylint my-custom-lints --path ./lint-libraries/my-custom-lints

# Run alongside clippy
cargo dylint my-custom-lints --all -- -- -D warnings
```

## Marker (Experimental)

[Marker](https://github.com/rust-marker/marker) is an experimental lint framework that does not require nightly Rust or `rustc_private`.

```rust
// marker_lint = "0.3"

use marker_api::*;

#[lint]
pub struct NoUnwrap;

impl LintPass for NoUnwrap {
    fn check_expr(&mut self, cx: &LateContext, expr: &ExprKind) {
        if let ExprKind::MethodCall(name, ..) = expr {
            if name == "unwrap" {
                cx.emit_warning("avoid using `.unwrap()` — use `?` or `.context()?` instead");
            }
        }
    }
}
```

Marker is less mature than Dylint but does not require nightly. Evaluate based on your project's Rust version requirements.

## Comparison

| Feature | Dylint | Marker |
|---------|--------|--------|
| Rust version | Nightly (`rustc_private`) | Stable |
| Maturity | Production (v2.1.3) | Experimental |
| API stability | Stable | Rapidly evolving |
| Lint library format | Dynamic library | Proc macro / plugin |
| Clippy integration | Runs alongside clippy | Separate |

## Recommendations

- **First choice**: Clippy — for all standard lints
- **Custom lints needed, nightly OK**: Dylint
- **Custom lints needed, stable only**: Marker (with caveats)
- **Before creating a custom lint**: Consider if the pattern can be caught by existing clippy lints with configuration

## See Also

- [Dylint GitHub repository](https://github.com/trailofbits/dylint)
- [Dylint documentation](https://trailofbits.github.io/dylint/)
- [Marker GitHub repository](https://github.com/rust-marker/marker)
- [Clippy lints list](https://rust-lang.github.io/rust-clippy/master/)
