# lint-warn-suspicious

**Rule**: `lint-warn-suspicious`

> Enable clippy::suspicious for likely bugs

## Why It Matters

The `clippy::suspicious` lint group catches code patterns that are syntactically valid but almost always wrong. These are potential bugs that deserve investigation. The shared strict gate denies the entire group; isolated general-purpose projects may choose a warning baseline. Several related lints have also been uplifted to rustc.

## Configuration

```toml
# Cargo.toml — canonical configuration
[lints.clippy]
suspicious = "warn"
```

Or stricter:

```toml
[lints.clippy]
suspicious = { level = "deny", priority = -1 }
```

## What It Catches

Use the compiler's actual group membership, not a guess from a lint's name.
For example, these are suspicious lints:

| Lint | Description |
|------|-------------|
| `suspicious_arithmetic_impl` | Unusual operator in an arithmetic trait implementation |
| `suspicious_assignment_formatting` | Misleading spacing around assignment and unary operators |
| `suspicious_else_formatting` | Misleading formatting around an else branch |
| `suspicious_map` | A mapped value is discarded by an operation such as `count()` |
| `suspicious_op_assign_impl` | Unusual operator in an op-assign implementation |
| `suspicious_unary_op_formatting` | Misleading spacing around unary operators |

<!-- rust-check: compile -->
```rust
fn count_values(values: &[u32]) -> usize {
    // The mapped values are never used by count().
    values.iter().map(|&value| value + 1).count()
}
```

Use `values.len()` here. If actual side effects are needed, express them as
a loop or a traversal that explicitly performs them; do not rely on mapped
values that are merely discarded.

Other potentially suspicious-looking code belongs to different groups:
`suspicious_splitn`, `modulo_one`, and `impossible_comparisons` are correctness;
`precedence` is complexity; `format_in_format_args` is perf. An assignment
expression in an `if` condition produces a Rust type error, not a Clippy lint.

## Uplifted Rustc Lints (Suspicious Category)

Several rustc lints complement the `clippy::suspicious` group. Configure them under `[lints.rust]`:

```toml
[lints.rust]
semicolon_in_expressions_from_macros = "deny"  # 1.91
dangerous_implicit_autorefs           = "deny"  # 1.89
integer_to_ptr_transmutes             = "warn"  # 1.91
const_item_interior_mutations         = "warn"  # 1.93
function_casts_as_integer             = "warn"  # 1.93
```

| Lint | Since | Level | What It Catches |
|------|-------|-------|-----------------|
| `semicolon_in_expressions_from_macros` | 1.91 | deny | Semicolon in macro expression position |
| `dangerous_implicit_autorefs` | 1.89 | deny | Unexpected implicit autoref creates surprising borrows |
| `integer_to_ptr_transmutes` | 1.91 | warn | Transmuting integer to pointer |
| `const_item_interior_mutations` | 1.93 | warn | Mutable reference to const item |
| `function_casts_as_integer` | 1.93 | warn | Casting function pointer to integer |

## Do Not Suppress Suspicious Lints

Under the strict policy, members of `clippy::suspicious` are not suppressible with either `#[allow]` or `#[expect]`. Investigate the diagnostic and rewrite the implementation so the intended semantics are explicit. If a lint is demonstrably wrong for a general Rust pattern, fix or report the lint rather than creating a local permanent hole.

## See Also

- [lint-deny-correctness](./lint-deny-correctness.md) — Deny definite bugs
- [lint-warn-style](./lint-warn-style.md) — Style warnings
- [lint-warn-complexity](./lint-warn-complexity.md) — Complexity warnings
- [lint-uplifted](./lint-uplifted.md) — Tracking clippy lints uplifted to rustc
