# lint-edition-2024

> Use the `rust_2024_compatibility` lint group and `cargo fix --edition` to audit edition-sensitive code before switching to Rust 2024

**Rule**: `lint-edition-2024`

## Why It Matters

Rust editions can change parsing, name resolution, temporary lifetimes, safety requirements, and other language semantics while preserving compatibility for crates that stay on an older edition. The compiler therefore provides **migration lints** that find code whose meaning or validity changes when moving to Edition 2024.

Do not invent a hand-maintained list of supposed “Edition 2024 lints” with guessed default levels. Rust exposes the real `rust-2024-compatibility` lint group, and `cargo fix --edition` enables that migration machinery and applies machine-applicable rewrites.

Edition 2024 shipped with Rust 1.85. Later compilers, including Rust 1.98, may have additional ordinary lints, but those are not automatically “Edition 2024 lints.”

## Recommended Migration Workflow

From a clean working tree on the old edition:

```bash
cargo fix --edition
cargo test --all-features
cargo clippy --all-targets --all-features
cargo doc --no-deps
```

Then update `Cargo.toml`:

```toml
[package]
edition = "2024"
```

For a manual audit, the compatibility group can also be enabled explicitly:

```rust
#![warn(rust_2024_compatibility)]

fn main() {}
```

The group currently contains migration lints such as `keyword_idents_2024`, `if_let_rescope`, `impl_trait_overcaptures`, `missing_unsafe_on_extern`, `unsafe_attr_outside_unsafe`, `unsafe_op_in_unsafe_fn`, `tail_expr_drop_order`, and others. Use `rustc -W help` for the exact group membership of the compiler you are running.

## `unsafe_op_in_unsafe_fn`: Warn by Default in Edition 2024

Edition 2024 does **not** make this lint deny-by-default. It changes from allow-by-default on older editions to **warn-by-default** in Edition 2024.

An `unsafe fn` places a safety contract on its caller. The lint encourages a separate explicit `unsafe { ... }` block for operations whose preconditions the function body is asserting:

```rust
/// # Safety
/// `ptr` must be valid and aligned for one readable `u8`.
unsafe fn read_byte(ptr: *const u8) -> u8 {
    // SAFETY: guaranteed by the caller contract above.
    unsafe { *ptr }
}

fn main() {
    let value = 7_u8;
    // SAFETY: `&value` is valid and aligned for a readable u8.
    assert_eq!(unsafe { read_byte(&value) }, 7);
}
```

Projects may choose to raise this warning to `deny`, but that is project lint policy, not the Edition 2024 default.

## Unsafe Attributes Are a Language Requirement

Edition 2024 requires unsafe attributes such as `no_mangle`, `export_name`, and `link_section` to use the `unsafe(...)` form. This is stronger than a style preference:

```rust
// SAFETY: this crate controls the exported symbol name and ensures it is unique.
#[unsafe(no_mangle)]
pub extern "C" fn example_export() {}

fn main() {}
```

The migration lint `unsafe_attr_outside_unsafe` helps rewrite the syntax, but the programmer must still review the attribute's safety requirements.

## `extern` Blocks Must Be Marked Unsafe

Edition 2024 requires `extern` blocks to be `unsafe extern` blocks, making the responsibility for foreign declarations explicit. The `missing_unsafe_on_extern` migration lint helps find old declarations.

```rust
unsafe extern "C" {
    safe fn abs(input: i32) -> i32;
}

fn main() {
    assert_eq!(abs(-4), 4);
}
```

Individual declarations inside an unsafe extern block can be marked `safe` when calling them really is safe for all inputs admitted by the Rust signature. Otherwise foreign functions remain unsafe to call.

## `gen` Became a Reserved Keyword

The new Edition 2024 reserved keyword is `gen`. Code on an older edition may legally have an identifier named `gen`; the `keyword_idents_2024` migration lint rewrites it to a raw identifier so the code remains valid after migration.

Old-edition source:

```text
fn gen() {}

fn main() {
    gen();
}
```

Migration-compatible spelling:

```rust
fn r#gen() {}

fn main() {
    r#gen();
}
```

The lint is named `keyword_idents_2024`, not the generic `keyword_idents`.

## `if let` Temporary Scope Changed

Edition 2024 can drop temporaries created in an `if let` scrutinee before entering the `else` branch, whereas older editions could keep them alive until after the whole `if let` expression. This can be important for guards such as `RefCell` borrows and lock guards.

The `if_let_rescope` migration lint is deliberately conservative and is allow-by-default outside migration tooling. Review the behavior rather than assuming “all temporaries now drop immediately after the condition.” If a pattern binding borrows from a temporary, ordinary borrow checking still has to keep the borrowed value valid for its use.

When old drop order must be preserved, an equivalent `match` can make the lifetime explicit.

## Return-Position `impl Trait` Captures More in Edition 2024

Edition 2024 changes default lifetime/type-parameter capture for return-position `impl Trait`. The migration lint is `impl_trait_overcaptures`. Use precise capturing syntax such as `use<...>` when an API needs a narrower capture set.

This is different from the unrelated `anonymous_lifetime_in_impl_trait` lint and should not be represented by that lint name.

## Let Chains Are a Language Feature, Not a Migration Lint

Let chains stabilized in Rust 1.88 and are available only to Edition 2024 crates. They allow conditions such as:

```rust
fn ordered(left: Option<i32>, right: Option<i32>) -> bool {
    if let Some(a) = left
        && let Some(b) = right
        && a < b
    {
        true
    } else {
        false
    }
}

fn main() {
    assert!(ordered(Some(1), Some(2)));
}
```

Do not describe let chains as a Clippy complexity lint or as something “stabilized by setting the edition.” Rust 1.88 stabilized the syntax; the syntax is edition-gated to 2024.

## There Is No Rust `strict_module_headers` Lint

`strict_module_headers` is not a rustc Edition 2024 lint. Do not configure it in `[lints.rust]`, and do not teach it as a warning for missing module documentation or `#[path]` usage.

For module documentation, use the real documentation lints such as `missing_docs` or `missing_crate_level_docs` as appropriate. For Edition migration, use the real compatibility group.

## Practical Guidance

- Run `cargo fix --edition` before changing the manifest edition.
- Review every safety-related automatic rewrite; migration tooling cannot prove your safety invariants.
- Treat `rust_2024_compatibility` as a migration aid, not a permanent substitute for understanding semantic changes.
- Do not guess default lint levels; query the compiler version you actually support with `rustc -W help`.
- Keep rustc edition lints separate from Clippy's `style`, `complexity`, `perf`, and other groups.
- After migration, run tests, Clippy, and rustdoc under the new edition.

## References

- [Rust Edition Guide — Rust 2024](https://doc.rust-lang.org/edition-guide/rust-2024/)
- [rustc lint groups](https://doc.rust-lang.org/rustc/lints/groups.html)
- [Rust 1.85 / Edition 2024 release](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)

## See Also

- [lint-unsafe-doc](./lint-unsafe-doc.md) — Safety documentation
- [lint-lints-table](./lint-lints-table.md) — Cargo lint configuration
- [lint-warn-complexity](./lint-warn-complexity.md) — Clippy complexity group
- [lint-warn-style](./lint-warn-style.md) — Clippy style group
