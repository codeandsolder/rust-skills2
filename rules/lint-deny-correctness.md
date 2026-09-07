# lint-deny-correctness

**Rule**: `lint-deny-correctness`

> Deny clippy::correctness and equivalent rustc lints

## Why It Matters

Correctness lints catch code that is outright wrong — logic errors, undefined behavior, or code that doesn't do what you think. These should always be errors, not warnings. Many Clippy correctness lints are now being uplifted to the Rust compiler.

CI also commonly wants lint warnings from local workspace packages to fail the build. Before Cargo 1.97, projects often reached for `RUSTFLAGS=-Dwarnings`, which changes compiler flags and therefore build-cache identities. Cargo 1.97 added a native warning policy: `CARGO_BUILD_WARNINGS=deny` (equivalent to Cargo's `build.warnings = "deny"`) can make local-package lint warnings fail the build without injecting a warning flag into `RUSTFLAGS`.

These are related but distinct controls:

- `[lints.rust]` / `[lints.clippy]` define source lint policy;
- `CARGO_BUILD_WARNINGS=deny` asks Cargo to fail a local package when Cargo-observed lint warnings remain;
- `cargo clippy -- -D warnings` promotes the rustc/Clippy `warnings` lint group for that invocation.

Cargo's build-warning policy is not a general “every line written by every build tool is fatal” switch. Build-script output and external-tool diagnostics have their own semantics.

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

On Cargo 1.97+ CI jobs can make local-package lint warnings fatal without altering `RUSTFLAGS`:

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

Rust 1.97 stopped hiding output from successful linker invocations. Linker diagnostics are emitted through the `linker_messages` rustc lint, which is `warn` by default.

`linker_messages` is deliberately **not** part of rustc's ordinary `warnings` lint group, so `-D warnings` does not by itself turn a linker message into an error. This matters because linker output is platform/toolchain dependent and rustc cannot classify it as precisely as compiler diagnostics.

Cargo's newer build-warning policy is a separate layer. As of Cargo 1.97/1.98, `CARGO_BUILD_WARNINGS=deny` can still cause a crate to fail when `linker_messages` produces a warning, despite `linker_messages` being excluded from rustc's `warnings` group. Treat that interaction as stricter and platform-sensitive rather than assuming the two warning mechanisms are equivalent.

If a supported linker emits known harmless chatter and a cross-platform CI job uses `CARGO_BUILD_WARNINGS=deny`, investigate the message first. If it is genuinely unavoidable, allow the lint deliberately and document the platform reason:

```toml
[lints.rust]
linker_messages = "allow"
```

Prefer fixing real linker warnings. Do not globally suppress `linker_messages` merely because a compiler upgrade exposed output that previous Rust versions hid.

## Running Clippy

```bash
# Basic check
cargo clippy

# With the ordinary rustc/Clippy warnings lint group as errors
cargo clippy -- -D warnings

# Check specific lint category
cargo clippy -- -W clippy::correctness

# Cargo 1.97+: fail local-package lint warnings without RUSTFLAGS
CARGO_BUILD_WARNINGS=deny cargo clippy -- -D warnings
```

`CARGO_BUILD_WARNINGS=deny` can be paired with Cargo's `--keep-going` when a CI job wants to collect more failures before exiting rather than stopping at the first affected package.

## See Also

- [lint-warn-suspicious](lint-warn-suspicious.md) — Warn on suspicious code
- [lint-warn-perf](lint-warn-perf.md) — Warn on performance issues
- [lint-uplifted](lint-uplifted.md) — Tracking clippy lints uplifted to rustc
- [lint-lints-table](lint-lints-table.md) — `[lints]` table configuration
- [proj-msrv-declare](proj-msrv-declare.md) — separate compatibility-floor and current-stable CI lanes