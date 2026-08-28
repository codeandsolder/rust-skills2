# perf-black-box-bench

> Use `std::hint::black_box` in benchmarks when compile-time knowledge could make the measured work unrealistically disappear or specialize.

## Why It Matters

Optimized benchmark code is still optimized code. If the compiler can prove an input is constant or a result is irrelevant, it may fold, simplify, or remove work that would exist in the real program.

`std::hint::black_box` tells the compiler to be maximally pessimistic about what can be assumed across that point. It is useful for benchmarks, but it is deliberately **best effort**: code generation varies by backend and target, and `black_box` provides no correctness, security, constant-time, or exact “this optimization is impossible” guarantee.

## Bad: Give the Optimizer the Entire Answer

<!-- rust-check: compile -->
```rust
fn expensive_computation(value: u64) -> u64 {
    (0..64).fold(value, |acc, n| acc.rotate_left(n % 63 + 1) ^ n as u64)
}

fn benchmark_shape_bad() {
    for _ in 0..1_000 {
        // Constant input and ignored result give an optimizer unusually strong
        // knowledge compared with a real caller.
        let _ = expensive_computation(42);
    }
}
```

This code may still execute in a particular build. The problem is that the benchmark does not constrain optimizations that make the measurement unrepresentative.

## Good: Hide Relevant Inputs and Consume Outputs

<!-- rust-check: compile -->
```rust
use std::hint::black_box;

fn expensive_computation(value: u64) -> u64 {
    (0..64).fold(value, |acc, n| acc.rotate_left(n % 63 + 1) ^ n as u64)
}

fn benchmark_shape_good(input: u64) {
    for _ in 0..1_000 {
        let result = expensive_computation(black_box(input));
        black_box(result);
    }
}
```

Use `black_box` at the boundary where compile-time knowledge would otherwise be unrealistic. Do not sprinkle it everywhere: every barrier can also inhibit optimizations that real production callers would legitimately get.

## Criterion Example

The repository's Criterion dependency can use the standard-library primitive directly:

<!-- rust-check: compile -->
```rust
use criterion::Criterion;
use std::hint::black_box;

fn parse_number(text: &str) -> u64 {
    text.parse().unwrap()
}

fn benchmark_parse(c: &mut Criterion) {
    let input = String::from("123456789");

    c.bench_function("parse_number", |b| {
        b.iter(|| {
            let value = parse_number(black_box(input.as_str()));
            black_box(value)
        })
    });
}
```

A benchmark framework may also expose/re-export a black-box helper, but using `std::hint::black_box` makes the language/toolchain primitive explicit.

## What `black_box` Actually Promises

`black_box(value)` is semantically an identity function: it returns `value` unchanged. Optimizer behavior around it is a hint.

Do **not** claim that it guarantees any of these:

- a function call cannot be inlined,
- a loop must execute in exactly the source-written form,
- a particular instruction sequence is preserved,
- cryptographic code becomes constant-time,
- all dead-code or constant-folding transformations are impossible.

For benchmarks, the intended best-effort pessimism is normally enough to stop obviously unrealistic whole-expression elimination and constant specialization.

## Inputs, Outputs, and Setup

Ask what the benchmark is supposed to include.

<!-- rust-check: compile -->
```rust
use std::hint::black_box;

fn process(data: &[u64]) -> u64 {
    data.iter().copied().sum()
}

fn benchmark_shape() {
    // Setup outside the measured operation when allocation/setup is not part
    // of the question being measured.
    let data = (0..1_000).collect::<Vec<u64>>();

    for _ in 0..100 {
        let result = process(black_box(&data));
        black_box(result);
    }
}
```

If setup cost is part of the real operation, keep it inside the measured region instead. Benchmark boundaries are part of the experiment design.

## Do Not Use `black_box` to Manufacture Cold Paths

`core::hint::cold_path()` expresses an optimizer belief that a path is unlikely. It does not make a benchmark of that path more realistic, and combining hints mechanically can measure an artificial code shape.

If you want to benchmark an error/cold path, construct representative inputs that actually take it. Use `black_box` only where compile-time knowledge of those inputs/results would distort the experiment.

## Validate Benchmark Quality

A useful microbenchmark should also consider:

- realistic input distributions and sizes,
- warm-up/sample noise and confidence intervals,
- whether allocations/I/O/setup belong inside the measured region,
- whether the optimized release configuration matches production,
- whether a microbenchmark improvement changes end-to-end behavior at all.

`black_box` fixes one class of benchmark artifact; it does not validate the experiment by itself.

## See Also

- [test-criterion-bench](./test-criterion-bench.md) - Criterion benchmarks
- [perf-profile-first](./perf-profile-first.md) - Find real hot spots first
- [perf-release-profile](./perf-release-profile.md) - Benchmark release-like builds
