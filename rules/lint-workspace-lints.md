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
unsafe_op_in_unsafe_fn = "deny"
unfulfilled_lint_expectations = "deny"
unexpected_cfgs = "warn"
rust_2024_compatibility = { level = "warn", priority = -1 }
missing_docs = "warn"

[workspace.lints.clippy]
# Correctness
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"

# Strict style/complexity for AI-maintained code
pedantic = { level = "deny", priority = -1 }
nursery = { level = "deny", priority = -1 }
style = { level = "deny", priority = -1 }
complexity = { level = "deny", priority = -1 }
perf = { level = "deny", priority = -1 }

[workspace.lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "warn"

# crate-a/Cargo.toml
[lints]
workspace = true

# crate-b/Cargo.toml
[lints]
workspace = true

# Cargo issue #13157 prevents manifest-level per-crate overrides when
# workspace = true is set. Prefer narrow code-level #[expect(..., reason = "...")]
# for genuinely suppressible lints; non-negotiable CI lints should be forbid.
```

## Recommended Lint Configuration

```toml
# Root Cargo.toml
[workspace.lints.rust]
# Safety
unsafe_code = "deny"
unsafe_op_in_unsafe_fn = "deny"       # Edition 2024
missing_debug_implementations = "warn"

# Edition migration / configuration hygiene
rust_2024_compatibility = { level = "warn", priority = -1 }
unexpected_cfgs = "warn"
unfulfilled_lint_expectations = "deny"

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

> **CRITICAL**: Cargo issue [#13157](https://github.com/rust-lang/cargo/issues/13157) — when `[lints] workspace = true` is set, member `Cargo.toml` files **cannot** override individual lints. For a genuinely suppressible lint, use the narrowest code-level `#[expect(..., reason = "...")]`. Do not use an expectation to waive correctness/safety policy.

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

### Correct Approach — Narrow, reasoned expectation

```rust
#[expect(
    clippy::too_many_lines,
    reason = "generated protocol dispatch table; splitting it obscures the mapping"
)]
fn generated_dispatch(/* ... */) {
    // ...
}
```

For non-negotiable lints such as `unwrap_used`, `expect_used`, explicit
`panic!`, undocumented unsafe blocks, or lock guards held across `await`,
fix the code instead of adding an expectation. The reusable strict gate passes
these categories as `forbid`, so source-level `#[allow]` and `#[expect]`
cannot lower them.

## CI Integration

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Strict Rust policy
        uses: codeandsolder/rust-skills2/.github/actions/rust-strict@main
      
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
style       = { level = "deny", priority = -1 }
complexity  = { level = "deny", priority = -1 }
perf        = { level = "deny", priority = -1 }
pedantic    = { level = "deny", priority = -1 }
nursery     = { level = "deny", priority = -1 }

# Keep unavoidable exceptions narrow and reasoned in source with #[expect].
# The central CI gate makes non-negotiable categories unsuppressible.
```

## Edition 2024 Workspace Lints

```toml
[workspace.lints.rust]
# Use rustc's real compatibility group instead of hand-maintaining guessed
# Edition lint names. Raise specific high-confidence rules separately.
rust_2024_compatibility = { level = "warn", priority = -1 }
unsafe_op_in_unsafe_fn = "deny"
unexpected_cfgs = "warn"
unfulfilled_lint_expectations = "deny"
```

## See Also

- [lint-deny-correctness](./lint-deny-correctness.md) - Critical lints
- [proj-workspace-deps](./proj-workspace-deps.md) - Workspace configuration
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) - unwrap lints
