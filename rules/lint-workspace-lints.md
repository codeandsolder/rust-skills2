# lint-workspace-lints

**Rule**: `lint-workspace-lints`

> Configure lints at workspace level for consistent enforcement

## Why It Matters

Without centralized lint configuration, each crate develops its own standards (or none). Workspace-level lints (Rust 1.74+) ensure consistent code quality across all crates. Denied lints catch issues in CI before they reach production.

## Bad

```toml
# crate-a/Cargo.toml - strict
[lints.clippy]
unwrap_used = "deny"

# crate-b/Cargo.toml - lenient
# No lint config

# crate-c/Cargo.toml - different
[lints.clippy]
unwrap_used = "warn"

# Inconsistent enforcement, some issues slip through
```

## Good

```toml
# Root Cargo.toml
[workspace.lints.rust]
unsafe_code = "deny"
unsafe_op_in_unsafe_fn = "deny"  # Edition 2024
missing_docs = "warn"
keyword_idents = "deny"          # Edition 2024

[workspace.lints.clippy]
# Correctness
unwrap_used = "deny"
expect_used = "warn"
panic = "deny"

# Style
needless_pass_by_value = "warn"
redundant_clone = "warn"

# Complexity
cognitive_complexity = "warn"

[workspace.lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "warn"

# crate-a/Cargo.toml
[lints]
workspace = true

# crate-b/Cargo.toml
[lints]
workspace = true

# Per-crate overrides must use code-level #![allow(...)]
# because Cargo issue #13157 prevents per-lint overrides
# when workspace = true is set.
```

## Recommended Lint Configuration

```toml
# Root Cargo.toml
[workspace.lints.rust]
# Safety
unsafe_code = "deny"
unsafe_op_in_unsafe_fn = "deny"       # Edition 2024
missing_debug_implementations = "warn"

# Edition 2024 lints
keyword_idents = "deny"
anonymous_lifetime_in_impl_trait = "deny"
if_let_rescope = "warn"
strict_module_headers = "warn"

# Quality
unused_results = "warn"
unused_qualifications = "warn"

[workspace.lints.clippy]
# === Correctness (deny) ===
correctness = { level = "deny", priority = -1 }

# === Suspicious (deny) ===
suspicious = { level = "deny", priority = -1 }

# === Style (warn) ===
style = { level = "warn", priority = -1 }

# === Complexity (warn) ===
complexity = { level = "warn", priority = -1 }

# === Perf (warn) ===
perf = { level = "warn", priority = -1 }

# === Pedantic (selective) ===
# Not all pedantic lints are useful
doc_markdown = "warn"
needless_pass_by_value = "warn"
redundant_closure_for_method_calls = "warn"
semicolon_if_nothing_returned = "warn"

# === Nursery (selective) ===
cognitive_complexity = "warn"
useless_let_if_seq = "warn"

# === Restriction (selective) ===
unwrap_used = "deny"
expect_used = "warn"
dbg_macro = "warn"
print_stdout = "warn"  # Use logging instead
todo = "warn"

[workspace.lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "warn"
missing_crate_level_docs = "warn"
```

## Per-Crate Overrides

> **CRITICAL**: Cargo issue [#13157](https://github.com/rust-lang/cargo/issues/13157) — when `[lints] workspace = true` is set, member `Cargo.toml` files **cannot** override individual lints. The member must use code-level `#![allow(...)]` instead.

### Works (✅) — Full workspace inheritance, no overrides

```toml
# crate-a/Cargo.toml
[lints]
workspace = true
```

### Does NOT Work (❌) — Override ignored or error

```toml
# crate-b/Cargo.toml
[lints]
workspace = true

# This is IGNORED when workspace = true is set (Cargo issue #13157)
[lints.clippy]
unwrap_used = "allow"
```

### Correct Approach — Code-level allow

```rust
// crate-b/src/main.rs
// Binary entry point — allow unwrap for this crate
#![allow(clippy::unwrap_used)]
```

Or use a module-level allow:

```rust
// crate-b/src/lib.rs
// Test utilities can print
#![allow(clippy::print_stdout)]
```

## CI Integration

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy
      
      - name: Clippy
        run: cargo clippy --workspace --all-targets -- -D warnings
      
      - name: Rustdoc
        run: RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps
```

## Lint Categories

```toml
# Category-level configuration
[workspace.lints.clippy]
# All lints in category at once
correctness = { level = "deny", priority = -1 }
suspicious  = { level = "deny", priority = -1 }
style       = { level = "warn", priority = -1 }
complexity  = { level = "warn", priority = -1 }
perf        = { level = "warn", priority = -1 }
pedantic    = { level = "warn", priority = -1 }

# Then override specific lints with higher priority (0 = default)
missing_errors_doc = "allow"  # Override pedantic for this lint
```

## Edition 2024 Workspace Lints

```toml
[workspace.lints.rust]
# Edition 2024 lints — explicit, deny-by-default in Edition 2024
unsafe_op_in_unsafe_fn          = "deny"
keyword_idents                  = "deny"
anonymous_lifetime_in_impl_trait = "deny"
if_let_rescope                  = "warn"
strict_module_headers           = "warn"
```

## See Also

- [lint-deny-correctness](./lint-deny-correctness.md) - Critical lints
- [proj-workspace-deps](./proj-workspace-deps.md) - Workspace configuration
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) - unwrap lints
