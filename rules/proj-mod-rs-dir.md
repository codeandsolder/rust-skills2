# proj-mod-rs-dir

> Choose a consistent multi-file module layout; both `foo.rs` + `foo/` and `foo/mod.rs` are supported

## Why It Matters

Rust supports two ordinary filesystem layouts for a module with submodules. Neither is inherently more correct or more scalable. Pick the style that makes your project easy to navigate, and avoid mixing styles accidentally when consistency matters to the team.

## Adjacent Module File

```text
src/
├── lib.rs
├── user.rs
└── user/
    ├── model.rs
    └── repository.rs
```

```rust
// src/user.rs
mod model;
mod repository;

pub fn module_name() -> &'static str {
    "user"
}
```

With `mod user;` in the parent, `user.rs` is the module root and `user/` contains its children.

## `mod.rs` Module Root

```text
src/
├── lib.rs
└── user/
    ├── mod.rs
    ├── model.rs
    └── repository.rs
```

```rust
// src/user/mod.rs
mod model;
mod repository;

pub fn module_name() -> &'static str {
    "user"
}
```

With `mod user;` in the parent, `user/mod.rs` can instead be the module root.

Do not provide both `user.rs` and `user/mod.rs` for the same module. Choose one root layout for that module.

## Choose by Project Navigation, Not Submodule Count

Rules such as “use `mod.rs` above four submodules” are arbitrary. More useful considerations are:

- whether unique editor-tab filenames matter (`user.rs` is easier to distinguish than several `mod.rs` tabs);
- whether keeping every file for a module under one directory is more convenient;
- existing repository convention;
- tooling or lint rules the project intentionally enables.

A large project can use either layout successfully.

## Edition 2024: `gen` Is a Keyword

Edition 2024 reserves `gen`. Existing identifiers can remain spelled `gen` by using a raw identifier in Rust source:

```rust
mod r#gen {
    pub fn generate() -> u32 {
        42
    }
}

fn main() {
    assert_eq!(r#gen::generate(), 42);
}
```

For a file module, the source declaration can be `mod r#gen;` while the filesystem name remains the ordinary module name, such as `gen.rs` or `gen/mod.rs`. Do **not** rename the file to `r#gen.rs`; `r#` is Rust source syntax, not part of the identifier's filesystem name.

For edition migration, `cargo fix --edition` uses the `keyword_idents_2024` compatibility lint to rewrite affected source identifiers to raw identifiers where appropriate. Renaming the module to something clearer such as `generator` is also reasonable when you control the API.

## Clippy Can Enforce Either Layout

These are restriction lints, not default Rust style rules:

```toml
# Cargo.toml
[lints.clippy]
mod_module_files = "warn"        # bans mod.rs; prefers foo.rs + foo/
```

Or, for the opposite convention:

```toml
# Cargo.toml
[lints.clippy]
self_named_module_files = "warn" # requires foo/mod.rs-style roots
```

Do not enable both. They intentionally prescribe opposite filesystem layouts.

## Keep Module Roots Useful

Whichever layout you choose, module roots are good places for the module's public surface and internal structure:

```rust
mod parser {
    mod lexer {
        pub(super) fn token_count(input: &str) -> usize {
            input.split_whitespace().count()
        }
    }

    pub fn tokens(input: &str) -> usize {
        lexer::token_count(input)
    }
}

fn main() {
    assert_eq!(parser::tokens("a b c"), 3);
}
```

Avoid turning filesystem style into an architecture rule. Module boundaries, visibility, and public re-exports matter more than whether the root happens to be named `mod.rs`.

## See Also

- [proj-flat-small](./proj-flat-small.md) — keep small projects simple
- [proj-mod-by-feature](./proj-mod-by-feature.md) — organize modules by responsibility
- [proj-pub-use-reexport](./proj-pub-use-reexport.md) — shape the public module surface
