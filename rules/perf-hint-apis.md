# perf-hint-apis

> Use compiler hint APIs only when their semantics match a measured hot path; they are advisory optimizations, not code-generation guarantees

**Rule**: `perf-hint-apis`

## Why It Matters

`std::hint` exposes a few specialized optimization hints. They can influence code layout or branch lowering, but they do not command a particular CPU instruction and they can make performance worse when the workload does not match the hint.

Treat these APIs like other low-level performance tools: keep the ordinary control flow correct without the hint, benchmark representative inputs, and preserve the hint only when it produces a repeatable benefit.

## `cold_path`: Mark the Current Path as Unlikely

```rust
use std::hint::cold_path;

fn parse_nonempty(input: &str) -> Result<&str, &'static str> {
    if input.is_empty() {
        cold_path();
        return Err("input is empty");
    }

    Ok(input)
}

fn main() {
    assert_eq!(parse_nonempty("hello"), Ok("hello"));
    assert!(parse_nonempty("").is_err());
}
```

`cold_path()` tells the compiler that the path reaching the call is unlikely. The compiler may optimize hotter paths at the cold path's expense. Do not promise that code will be emitted into a specific section or that a branch will disappear; inspect/benchmark the target if those details matter.

For a reusable cold helper function, `#[cold]` may communicate the intent more naturally.

## `select_unpredictable`: Select Between Two Values

`select_unpredictable` takes **three arguments**: a condition, the value to return when true, and the value to return when false.

```rust
use std::hint::select_unpredictable;

fn sum_positive(values: &[i32]) -> i32 {
    values
        .iter()
        .copied()
        .map(|value| select_unpredictable(value > 0, value, 0))
        .sum()
}

fn main() {
    assert_eq!(sum_positive(&[-5, 7, -1, 3]), 10);
}
```

It is functionally equivalent to `if condition { true_val } else { false_val }`, plus a hint that the condition is hard for a branch predictor to predict. The optimizer **might** lower this to a conditional move/select instruction on a suitable target, but that lowering is not guaranteed.

A binary-search-style update is another plausible use:

```rust
use std::hint::select_unpredictable;

fn floor_index(values: &[u64], needle: u64) -> Option<usize> {
    if values.is_empty() || values[0] > needle {
        return None;
    }

    let mut base = 0usize;
    let mut size = values.len();

    while size > 1 {
        let half = size / 2;
        let mid = base + half;
        base = select_unpredictable(values[mid] <= needle, mid, base);
        size -= half;
    }

    Some(base)
}

fn main() {
    let values = [10, 20, 30, 40];
    assert_eq!(floor_index(&values, 25), Some(1));
    assert_eq!(floor_index(&values, 40), Some(3));
}
```

Do not use this API for predictable branches: the alternative lowering can be slower. It is also not a constant-time cryptography primitive.

## `assert_unchecked`: An Unsafe Soundness Promise

`assert_unchecked(condition)` tells the compiler that `condition` is true. If it is false, the program has immediate undefined behavior. This is fundamentally different from a debug assertion or ordinary branch hint.

```rust
use std::hint::assert_unchecked;

/// # Safety
/// `index` must be strictly less than `values.len()`.
unsafe fn get_known_in_bounds(values: &[u32], index: usize) -> u32 {
    // SAFETY: guaranteed by this function's caller contract.
    unsafe {
        assert_unchecked(index < values.len());
        *values.get_unchecked(index)
    }
}

fn main() {
    let values = [10, 20, 30];
    // SAFETY: 1 < values.len().
    assert_eq!(unsafe { get_known_in_bounds(&values, 1) }, 20);
}
```

Usually, write safe code in a form the optimizer can understand instead. `assert_unchecked` is appropriate only when the invariant is independently required for soundness/performance, its proof is clear, and measurement shows the extra promise matters.

## Do Not Turn Hints Into Performance Folklore

Avoid claims such as:

- `select_unpredictable` “emits CMOV”;
- `cold_path` always moves code into a `.cold` section;
- `assert_unchecked` always removes a bounds check;
- a hint that helps one CPU/compiler build must help another.

All three feed information to the optimizer. The final code depends on target, optimization level, surrounding code, compiler version, and profile data.

## Prefer Higher-Level Structure First

Before adding hints, check whether ordinary Rust already expresses the optimization opportunity:

- use iterators/slices to expose bounds relationships;
- hoist validation outside hot loops;
- separate genuinely cold error handling into a helper;
- use data layout or algorithm changes when branch behavior is the real bottleneck;
- consider profile-guided optimization for application-wide branch/layout information.

Hints are the last few percent, not a substitute for an appropriate algorithm.

## Quick Reference

| API | Stable since | Meaning | Important caveat |
|---|---:|---|---|
| `cold_path()` | 1.95 | current path is unlikely | advisory code-layout/optimization hint |
| `select_unpredictable(cond, a, b)` | 1.88 | choose `a`/`b`; condition is hard to predict | branchless lowering is not guaranteed |
| `unsafe { assert_unchecked(cond) }` | 1.81 | compiler may assume `cond == true` | false condition is immediate UB |

## See Also

- [perf-black-box-bench](./perf-black-box-bench.md) — benchmark barriers
- [opt-cold-unlikely](./opt-cold-unlikely.md) — cold functions
- [opt-bounds-check](./opt-bounds-check.md) — bounds-check elimination
- [perf-profile-first](./perf-profile-first.md) — measure before optimizing

## References

- [std::hint](https://doc.rust-lang.org/std/hint/)
- [std::hint::select_unpredictable](https://doc.rust-lang.org/std/hint/fn.select_unpredictable.html)
- [std::hint::cold_path](https://doc.rust-lang.org/std/hint/fn.cold_path.html)
- [std::hint::assert_unchecked](https://doc.rust-lang.org/std/hint/fn.assert_unchecked.html)
