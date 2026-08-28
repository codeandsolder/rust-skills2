# name-crate-no-rs

> Avoid `-rs`, `-rust`, `rust-`, and similar language-only affixes in crate/package names

## Why It Matters

The Rust API Guidelines explicitly recommend against `-rs` and `-rust` as crate-name prefixes or suffixes: the implementation language is already implied by the ecosystem. Prefer a name that identifies the library, protocol, domain, binding target, or other distinguishing purpose.

This is a naming guideline, not a registry rule. Cargo and crates.io can accept names containing `rust` or `rs`, and a real collision or cross-language repository family can justify disambiguation.

## Prefer Descriptive Names

```toml
# Avoid language-only suffixes/prefixes when they add no information.
[package]
name = "json-parser"
```

Better distinguishing words describe what the package does:

```toml
[package]
name = "sqlite-wrapper"
```

Standard ecosystem suffixes that convey meaning are different. For example, `-sys` conventionally identifies low-level native/FFI bindings such as `openssl-sys` or `libgit2-sys`.

## Package Name vs Rust Crate Name

Cargo package names and Rust crate identifiers are related but not identical. Cargo package names may contain `-`; Rust crate paths cannot. Unless an explicit target name overrides it, Cargo maps dashes to underscores for the library crate name.

```text
Cargo package:  json-parser
Rust crate path: json_parser

Cargo package:  http-client
Rust crate path: http_client
```

Both snake_case and kebab-case package names are accepted by Cargo. Current `cargo new`/`cargo init` recommend names that follow one of those styles; they do **not** warn merely because a valid package name contains dashes.

For example, a mixed-case package name is what triggers the style warning:

```text
$ cargo new MyProject
warning: the name `MyProject` is not snake_case or kebab-case ...
```

That warning behavior dates to Cargo 1.75 (released in 2023), not to the 2024 edition.

## Repository Names Are Separate

Repository names are not Rust crate identifiers. A repository may use an `-rs` suffix for practical disambiguation from sibling implementations, mirrors, or an existing project name even when the published Cargo package does not. Apply the guideline where it improves discoverability; do not turn it into a fake syntax rule.

## Decision Guide

| Situation | Prefer |
|---|---|
| Ordinary Rust library | Descriptive package name without language affix |
| Low-level native bindings | Conventional `-sys` name |
| Wrapper for a named external project | Name that identifies the wrapped project/purpose |
| Repository must distinguish several language implementations | Repository-specific suffix may be reasonable |
| crates.io/package namespace collision | Choose a meaningful qualifier before falling back to language-only noise |

## See Also

- [proj-workspace-deps](./proj-workspace-deps.md) - Cargo configuration
- [doc-cargo-metadata](./doc-cargo-metadata.md) - Package metadata
- [name-funcs-snake](./name-funcs-snake.md) - Rust item naming conventions

## References

- [Rust API Guidelines: naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [Cargo Book: manifest `package.name`](https://doc.rust-lang.org/cargo/reference/manifest.html#the-name-field)
- [Rust Reference: external crate names](https://doc.rust-lang.org/reference/items/extern-crates.html)
