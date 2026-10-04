# lint-uplifted

> Track Clippy lints uplifted into rustc and adjacent compiler lint changes (Rust 1.86-1.99)

**Rule**: `lint-uplifted`

## Why It Matters

Clippy lints are increasingly being uplifted into the Rust compiler (`rustc`). Uplifted lints run on every `rustc` invocation without needing clippy, give better diagnostics, and are enabled by default or opt-in via `[lints.rust]`. Tracking these uplifts prevents configuring a lint as a clippy lint when it is now built into the compiler.

## Uplifted Lints Since Rust 1.86

| Lint | Uplifted In | Default Level | Notes |
|------|-------------|---------------|-------|
| `missing_abi` | 1.86 | `warn` | Fn items missing `extern "..."` ABI specifier |
| `double_negations` | 1.86 | `warn` | `--x` where integer negation is applied twice |
| `invalid_null_arguments` | 1.88 | `deny` | Passing `null` to functions expecting non-null |
| `dangerous_implicit_autorefs` | 1.88 (warn) → 1.89 (deny) | `deny` | Implicit autoref to `&T` creating unexpected borrows |
| `integer_to_ptr_transmutes` | 1.91 | `warn` | Transmuting integers to pointers |
| `dangling_pointers_from_locals` | 1.91 | `warn` | Pointers to local variables that have been dropped |
| `const_item_interior_mutations` | 1.93 | `warn` | Mutable references to `const` items |
| `function_casts_as_integer` | 1.93 | `warn` | Casting function pointers to integer types |
| `unused_visibilities` | 1.94 | `warn` | Visibility modifiers that have no effect |
| `uninhabited_static` | 1.96 | `deny` | `static` or `const` of uninhabited types |
| `invalid_runtime_symbol_definitions` | 1.98 | `deny` | Invalid definitions of compiler/runtime symbols; expanded to POSIX symbols in 1.99 |
| `suspicious_runtime_symbol_definitions` | 1.98 | `warn` | Suspicious runtime symbol definitions; POSIX coverage expands in 1.99 |
| `c_void_returns` | 1.98 | `warn` | Flags `core::ffi::c_void` used as a Rust return type |

## Bad

```toml
# Configuring as clippy lint when it's now a compiler lint
[lints.clippy]
missing_abi = "deny"          # Uplifted, use [lints.rust] instead
double_negations = "deny"     # Uplifted, use [lints.rust] instead
```

## Good

```toml
# Configure uplifted lints under [lints.rust]
[lints.rust]
missing_abi                  = "deny"
double_negations             = "deny"
invalid_null_arguments       = "deny"
dangerous_implicit_autorefs  = "deny"
integer_to_ptr_transmutes    = "warn"
dangling_pointers_from_locals = "warn"
const_item_interior_mutations = "warn"
function_casts_as_integer    = "warn"
unused_visibilities          = "warn"
uninhabited_static           = "deny"\ninvalid_runtime_symbol_definitions = "deny"\nsuspicious_runtime_symbol_definitions = "warn"\nc_void_returns                 = "warn"
```


## Rust 1.99 Review Signals

Rust 1.99 adds or strengthens several compiler diagnostics that are worth
checking during a toolchain migration even though they are not all Clippy
uplifts:

- `raw_borrows_via_references` is allow-by-default and can expose raw-pointer
  code that creates a temporary reference only to immediately decay it to a
  raw pointer;
- `unreachable_cfg_select_predicates` now participates in the `unused` lint
  group, so stale or shadowed `cfg_select!` arms can start warning;
- `unconditional_panic` now recognizes zero-sized `chunks`/`windows`
  calls;
- `no_mangle_generic_items` is now a hard error rather than a future
  compatibility diagnostic;
- legacy integral modules such as `std::i32::MAX` are fully deprecated; use
  primitive associated constants such as `i32::MAX`.

Do not blanket-allow a newly surfaced diagnostic just to complete the compiler
upgrade. First decide whether it reveals stale configuration, an invalid FFI
boundary, or a raw-pointer pattern whose intended invariant should be stated
more directly.

## Migration Strategy

When upgrading the minimum Rust version, check which clippy lints have been uplifted:

```bash
# Check current Rust version
rustc --version

# Look for deprecation warnings from clippy about uplifted lints
cargo clippy 2>&1 | grep "has been uplifted"
```

When a clippy lint is deprecated due to uplift, clippy prints a warning like:

```
warning: lint `clippy::missing_abi` has been uplifted to `rustc::missing_abi`
```

Move the configuration from `[lints.clippy]` to `[lints.rust]` and remove the `clippy::` prefix.

## Workspace Configuration

```toml
# Workspace Cargo.toml
[workspace.lints.rust]
missing_abi                   = "deny"
double_negations              = "deny"
invalid_null_arguments        = "deny"
dangerous_implicit_autorefs   = "deny"
integer_to_ptr_transmutes     = "warn"
dangling_pointers_from_locals = "warn"
const_item_interior_mutations = "warn"
function_casts_as_integer     = "warn"
unused_visibilities           = "warn"
uninhabited_static            = "deny"\ninvalid_runtime_symbol_definitions = "deny"\nsuspicious_runtime_symbol_definitions = "warn"\nc_void_returns                 = "warn"
```

## See Also

- [Rust 1.86.0 release notes](https://blog.rust-lang.org/2025/04/03/Rust-1.86.0/) — `missing_abi`, `double_negations`
- [Rust 1.88.0 release notes](https://blog.rust-lang.org/2025/06/26/Rust-1.88.0/) — `invalid_null_arguments`, `dangerous_implicit_autorefs`
- [Rust 1.91.0 release notes](https://releases.rs/docs/1.91.0/) — `integer_to_ptr_transmutes`, `dangling_pointers_from_locals`
- [Rust 1.93.0 release notes](https://releases.rs/docs/1.93.0/) — `const_item_interior_mutations`, `function_casts_as_integer`
- [Rust 1.94.0 release notes](https://releases.rs/docs/1.94.0/) — `unused_visibilities`
- [Rust 1.96.0 release notes](https://releases.rs/docs/1.96.0/) — `uninhabited_static`
- [lint-deny-correctness](./lint-deny-correctness.md) — Correctness lint configuration
- [lint-lints-table](./lint-lints-table.md) — Lint configuration via `[lints]` table
