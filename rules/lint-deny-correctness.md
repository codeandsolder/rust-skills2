# lint-deny-correctness

**Rule**: `lint-deny-correctness`

> Deny clippy::correctness and equivalent rustc lints

## Why It Matters

Correctness lints catch code that is outright wrong — logic errors, undefined behavior, or code that doesn't do what you think. These should always be errors, not warnings. Many clippy correctness lints are now being uplifted to the Rust compiler.

## Bad

```toml
# No explicit correctness lint configuration — relying on defaults
[lints.clippy]
# missing: correctness = "deny"
```

## Good

```toml
# Cargo.toml — canonical config (Rust 1.74+)
[lints.clippy]
correctness = "deny"
suspicious  = "warn"
style       = "warn"
complexity  = "warn"
perf        = "warn"
```

For stricter enforcement:

```toml
[lints.clippy]
correctness = { level = "deny", priority = -1 }
suspicious  = { level = "deny", priority = -1 }
style       = { level = "warn", priority = -1 }
complexity  = { level = "warn", priority = -1 }
perf        = { level = "warn", priority = -1 }
```

## What It Catches

```rust
// Infinite loop (iter::repeat without take)
for x in std::iter::repeat(1) {  // ERROR: infinite iterator
    println!("{}", x);
}

// Comparison to NaN (always false)
if x == f64::NAN {  // ERROR: NaN != NaN always
    // This never executes
}

// Use after free patterns
let r;
{
    let x = 5;
    r = &x;  // ERROR: x dropped here
}
println!("{}", r);

// Wrong equality check
if x = 5 {  // ERROR: assignment in condition (should be ==)
}

// Useless comparisons
if x >= 0 && x < 0 {  // ERROR: impossible condition
}
```

## Uplifted Correctness Lints

Several lints previously in `clippy::correctness` have been uplifted to `rustc`. Configure them under `[lints.rust]` instead:

| Lint | Uplifted In | Level | What It Catches |
|------|-------------|-------|-----------------|
| `missing_abi` | 1.86 | warn | Missing `extern "..."` on fn items |
| `double_negations` | 1.86 | warn | `--x` double integer negation |
| `invalid_null_arguments` | 1.88 | deny | Null passed where non-null expected |
| `dangerous_implicit_autorefs` | 1.89 | deny | Unexpected implicit autoref borrows |
| `integer_to_ptr_transmutes` | 1.91 | warn | Transmuting integers to pointers |
| `dangling_pointers_from_locals` | 1.91 | warn | Pointers to dropped local variables |
| `const_item_interior_mutations` | 1.93 | warn | Mutable refs to const items |
| `function_casts_as_integer` | 1.93 | warn | Casting fn pointers to integers |
| `uninhabited_static` | 1.96 | deny | Static/const of uninhabited types |

```toml
# Uplifted rustc lints
[lints.rust]
missing_abi                    = "deny"
double_negations               = "deny"
invalid_null_arguments         = "deny"
dangerous_implicit_autorefs    = "deny"
integer_to_ptr_transmutes      = "warn"
dangling_pointers_from_locals  = "warn"
const_item_interior_mutations  = "warn"
function_casts_as_integer      = "warn"
uninhabited_static             = "deny"
```

## Running Clippy

```bash
# Basic check
cargo clippy

# With all warnings as errors
cargo clippy -- -D warnings

# Check specific lint category
cargo clippy -- -W clippy::correctness

# In CI (fail on warnings)
cargo clippy -- -D warnings -D clippy::correctness
```

## See Also

- [lint-warn-suspicious](lint-warn-suspicious.md) — Warn on suspicious code
- [lint-warn-perf](lint-warn-perf.md) — Warn on performance issues
- [lint-uplifted](lint-uplifted.md) — Tracking clippy lints uplifted to rustc
- [lint-lints-table](lint-lints-table.md) — `[lints]` table configuration
