# lint-deny-correctness

**Rule**: `lint-deny-correctness`

> Deny correctness lints, and on Cargo 1.97+ prefer Cargo-native warning denial in CI over injecting `-D warnings` through `RUSTFLAGS`

## Why It Matters

Correctness lints catch code that is outright wrong — logic errors, undefined behavior, or code that doesn't do what you think. These should always be errors, not warnings. Many Clippy correctness lints are now being uplifted to the Rust compiler.

CI also commonly wants to fail on ordinary compiler/build-script warnings. Before Cargo 1.97, projects often used `RUSTFLAGS=-Dwarnings`, which changes compiler flags and therefore build-cache identities. Cargo 1.97 added a native warning policy: `CARGO_BUILD_WARNINGS=deny` or the equivalent Cargo configuration can make warnings fail the build without perturbing the underlying rustc flags/cache key.

These are related but distinct controls:

- `[lints.rust]` / `[lints.clippy]` define source lint policy;
- `CARGO_BUILD_WARNINGS=deny` controls whether rendered Cargo build warnings make the command fail;
- `cargo clippy -- -D warnings` remains useful when you specifically want every rustc/Clippy lint emitted by that invocation promoted to error.

## Bad

```toml
# No explicit correctness lint configuration — relying on defaults
[lints.clippy]
# missing: correctness = "deny"
```

Also avoid making `RUSTFLAGS=-Dwarnings` the default CI mechanism purely to turn warnings into failures:

```yaml
# Avoid when Cargo 1.97+ is available: this changes rustc flags/cache identity.
env:
  RUSTFLAGS: -Dwarnings
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

On Cargo 1.97+ CI jobs can make Cargo warnings fatal without altering `RUSTFLAGS`:

```yaml
env:
  CARGO_BUILD_WARNINGS: deny

steps:
  - run: cargo check --locked --workspace --all-targets
  - run: cargo clippy --locked --workspace --all-targets -- -D warnings
```

For a local one-off command, the same policy can be applied only to that invocation:

```bash
CARGO_BUILD_WARNINGS=deny cargo check
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

## Rust 1.97+: Linker Messages Are Their Own Lint

Rust 1.97 stopped hiding successful-linker output by default. Linker diagnostics are emitted through the `linker_messages` rustc lint, which is `warn` by default.

Do **not** assume `-D warnings` or Cargo's build-warning policy is a portable reason to blindly deny every linker message. `linker_messages` is deliberately special and is not part of the ordinary `warnings` lint group because linker output is platform/toolchain dependent and rustc does not control it as precisely as compiler diagnostics.

If a specific supported linker emits known harmless chatter, allow the lint deliberately and document why:

```toml
[lints.rust]
linker_messages = "allow"
```

Prefer fixing real linker warnings first. Do not globally suppress `linker_messages` just because a newly upgraded compiler exposed previously hidden output.

## Running Clippy

```bash
# Basic check
cargo clippy

# With all rustc/Clippy warnings from this invocation as errors
cargo clippy -- -D warnings

# Check specific lint category
cargo clippy -- -W clippy::correctness

# Cargo 1.97+: fail the build on Cargo-rendered warnings without RUSTFLAGS
CARGO_BUILD_WARNINGS=deny cargo clippy -- -D warnings
```

`CARGO_BUILD_WARNINGS=deny` can be paired with Cargo's `--keep-going` when a CI job wants to collect more failures before exiting rather than stopping at the first package warning/error.

## See Also

- [lint-warn-suspicious](lint-warn-suspicious.md) — Warn on suspicious code
- [lint-warn-perf](lint-warn-perf.md) — Warn on performance issues
- [lint-uplifted](lint-uplifted.md) — Tracking clippy lints uplifted to rustc
- [lint-lints-table](lint-lints-table.md) — `[lints]` table configuration
- [proj-msrv-declare](proj-msrv-declare.md) — separate compatibility-floor and current-stable CI lanes