# opt-select-unpredictable

> Consider `core::hint::select_unpredictable` for measured, hard-to-predict value selections; neither branchless lowering nor constant-time execution is guaranteed (Rust 1.88+)

## Why It Matters

A mispredicted branch can waste CPU work. When a condition is frequently
mispredicted, the optimizer may instead use a conditional move or select
instruction. `select_unpredictable` conveys that probability information;
it does not require any particular instruction or ensure faster code.

## Ordinary Baseline

Prefer the standard search when its semantics fit:

```rust
fn search(data: &[i32], target: i32) -> Option<usize> {
    data.binary_search(&target).ok()
}
```

The slice must be sorted. When duplicates exist, any matching index is
acceptable. Benchmark before reimplementing this operation.

## Good: Measured Value Selection

The following illustrates the selection inside a search for the last element
less than or equal to the target. Check the selected index for equality.
The initial empty-slice/first-element guard is necessary to establish the
invariant that the base is a valid candidate.

<!-- rust-check: run -->
```rust
use core::hint::select_unpredictable;

fn search(data: &[i32], target: i32) -> Option<usize> {
    if data.is_empty() || data[0] > target {
        return None;
    }

    let mut base = 0;
    let mut size = data.len();
    while size > 1 {
        let half = size / 2;
        let mid = base + half;
        base = select_unpredictable(data[mid] <= target, mid, base);
        size -= half;
    }

    (data[base] == target).then_some(base)
}

fn main() {
    // Exercise empty, singleton, even and odd lengths, duplicates and misses.
    for len in 0..=65 {
        let data: Vec<i32> = (0..len).map(|i| i / 3 - 10).collect();
        for target in -12..=14 {
            assert_eq!(
                search(&data, target),
                data.iter().rposition(|&value| value == target),
            );
        }
    }
}
```

This code chooses a specific duplicate (the last matching element). A plain
`if` with the same update is a useful comparison in the benchmark. A
strict-less-than comparison would incorrectly miss exact upper elements
in this algorithm.

## How It Works

Both arguments are evaluated before `select_unpredictable` is called,
unlike the mutually exclusive arms of an `if` expression. Avoid expensive
or side-effecting operands and do not use this function to guard invalid
memory accesses. The unselected value is dropped.

Select typed values directly, including function pointers if appropriate:

```rust
use core::hint::select_unpredictable;

fn dispatch(condition: bool, fast: fn(), slow: fn()) {
    let selected = select_unpredictable(condition, fast, slow);
    selected();
}
```

No pointer-to-integer conversion or unsafe transmutation is necessary.
An indirect call need not be faster than an ordinary conditional call.
Neither a data-dependent search nor this dispatch is a constant-time
cryptographic primitive.

## When to Use

- Measure a hard-to-predict selection in a hot path; compare against ordinary control flow.
- Use simple, cheap candidates. Predictable branches or expensive arms may favor an `if`.
- Inspect optimized assembly for the actual target and benchmark representative inputs.
  A conditional move can increase data dependencies; a branch can be faster.
- Do not interpret the presence or absence of one instruction as a proof of
  whole-function performance, side-channel behavior, or correctness.

## See Also

- [opt-likely-hint](./opt-likely-hint.md) — branch probability hints
- [opt-cold-path](./opt-cold-path.md) — cold inline paths
- [perf-hint-apis](./perf-hint-apis.md) — semantics of the compiler hint APIs
- [perf-profile-first](./perf-profile-first.md) — profile before optimizing
- [Standard library: select_unpredictable](https://doc.rust-lang.org/std/hint/fn.select_unpredictable.html)
