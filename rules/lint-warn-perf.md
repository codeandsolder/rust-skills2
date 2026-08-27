# lint-warn-perf

**Rule**: `lint-warn-perf`

> Enable `clippy::perf` for established performance anti-patterns; measure before adding optimizer hints

## Why It Matters

`clippy::perf` contains lints for patterns that are commonly more expensive than a straightforward alternative: redundant allocations, unnecessary cloning, avoidable indirection, and inefficient collection access. It is a useful default warning group, but it is not a profiler and it does not prove that a linted expression matters to your workload.

Compiler hints such as `std::hint::select_unpredictable` and `std::hint::cold_path` are a separate tool. They can change code generation, but their effect is intentionally not guaranteed and can make performance worse when the hint does not match reality.

## Configuration

In a crate root:

```rust
#![warn(clippy::perf)]

fn main() {}
```

Or in `Cargo.toml`:

```toml
[lints.clippy]
perf = "warn"
```

For libraries with an MSRV, configure Clippy consistently with that MSRV before accepting suggestions that rely on newer standard-library APIs.

## Representative `clippy::perf` Lints

The exact lint set evolves with Clippy. Current examples include:

| Lint | Typical issue |
|---|---|
| `box_collection` | Adds a redundant heap indirection around an already heap-backed collection |
| `boxed_local` | Boxes a local value when ownership does not require allocation |
| `cmp_owned` | Creates an owned value only to compare it |
| `iter_nth` | Uses iterator stepping on a standard collection that has direct indexed access |
| `iter_overeager_cloned` | Clones items before adapters that may discard most of them |
| `large_enum_variant` | A large variant inflates every value of the enum |
| `redundant_allocation` | Adds an unnecessary layer of allocation/indirection |
| `slow_vector_initialization` | Builds a zero-filled vector through a slower multi-step pattern |

Do not assume every style-looking suggestion belongs to `clippy::perf`. Clippy has separate `style`, `complexity`, `correctness`, `suspicious`, and other groups.

## Good: Fix the Cost, Not Merely the Spelling

```rust
fn keep_first_ten(values: &[String]) -> Vec<String> {
    values.iter().take(10).cloned().collect()
}

fn contains_name(names: &[String], wanted: &str) -> bool {
    names.iter().any(|name| name == wanted)
}

fn main() {
    let names = vec!["Ada".to_owned(), "Grace".to_owned()];
    assert!(contains_name(&names, "Ada"));
    assert_eq!(keep_first_ten(&names).len(), 2);
}
```

The useful transformation is usually semantic: postpone cloning until after filtering/taking, compare borrowed values directly, or remove an allocation layer. Do not mechanically rewrite code simply because two spellings look similar.

## `select_unpredictable` (Rust 1.88+)

`select_unpredictable(condition, true_val, false_val)` is functionally equivalent to an `if` expression, while telling the optimizer that the condition is difficult for a CPU branch predictor.

```rust
use std::hint::select_unpredictable;

fn choose(condition: bool, left: u32, right: u32) -> u32 {
    select_unpredictable(condition, left, right)
}

fn main() {
    assert_eq!(choose(true, 10, 20), 10);
    assert_eq!(choose(false, 10, 20), 20);
}
```

On targets with conditional-select instructions, the optimizer **might** choose branchless code. That lowering is not guaranteed. Do not use this as a constant-time cryptography primitive, and benchmark it against an ordinary `if`; a predictable branch may be faster.

## `cold_path` (Rust 1.95+)

`cold_path()` marks the path containing the call as unlikely. It takes no arguments and returns `()`.

```rust
use std::hint::cold_path;

fn classify(value: i32) -> &'static str {
    if value >= 0 {
        "ordinary"
    } else {
        cold_path();
        "exceptional"
    }
}

fn main() {
    assert_eq!(classify(1), "ordinary");
    assert_eq!(classify(-1), "exceptional");
}
```

Like other optimizer hints, `cold_path` is advisory. Use it only for paths that are genuinely rare and where measurement shows a benefit.

## Allocation Guidance

`Vec::new()` and `vec![]` both create an empty vector without allocating element storage. The useful optimization is normally to avoid an allocation altogether or reserve capacity when the final size is reasonably predictable.

```rust
fn squares(count: usize) -> Vec<usize> {
    let mut out = Vec::with_capacity(count);
    for value in 0..count {
        out.push(value * value);
    }
    out
}

fn main() {
    assert_eq!(squares(4), vec![0, 1, 4, 9]);
}
```

`with_capacity` is not automatically better: substantial over-reservation wastes memory, and tiny vectors may not justify forecasting capacity.

## Single-Character Patterns

When the operation really is about one character, a `char` pattern can express that directly and may enable a simpler implementation. Treat this as an API/measurement choice, not a universal statement that every one-character `&str` is measurably slow.

```rust
fn contains_comma(text: &str) -> bool {
    text.contains(',')
}

fn main() {
    assert!(contains_comma("a,b"));
}
```

## Practical Guidance

- Enable `clippy::perf` as a warning group and review its findings rather than blindly applying them.
- Keep the project's MSRV in mind when Clippy suggests newer APIs.
- Prefer removing allocations/copies to micro-tuning syntax.
- Profile before changing hot code on performance grounds.
- Treat `select_unpredictable` and `cold_path` as measured, advisory hints—not code-generation contracts.

## See Also

- [lint-warn-complexity](./lint-warn-complexity.md) - Complexity warnings
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocation
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
- [opt-bounds-check](./opt-bounds-check.md) - Bounds-check-sensitive loops
