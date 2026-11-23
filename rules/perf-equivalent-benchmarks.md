# Benchmark equivalent work before choosing a faster abstraction

> Compare implementations on the same semantics, inputs, outputs, allocation policy and execution model; use microbenchmarks to identify hypotheses, not to justify unconditional performance rules.

## Why It Matters

The [less_slow.rs](https://github.com/ashvardanian/less_slow.rs) experiments compare closure, iterator, trait-object, experimental coroutine and async-stream pipelines. They illustrate the cost of dispatch and suspension, but their results are specific to a small CPU-bound prime-factorization pipeline. The stream variant also uses an executor, and the virtual variant materializes intermediate vectors; those differences are part of the measured architecture, not isolated dispatch overhead.

Before optimizing, check that candidates implement the same operation and return the same values. Measure end-to-end throughput as well as isolated stages. Separate setup, allocation, scheduling, and per-item processing when the question requires it. Benchmark representative input distributions, sizes, warm/cold cache conditions, and target CPUs. Check generated code or profiles when attributing differences to a particular abstraction.

Numerical shortcuts are a **different algorithm**, not an interchangeable faster implementation: a truncated Maclaurin sine polynomial is inaccurate outside its useful domain, and fast floating-point intrinsics can change NaN, infinity, signed-zero, reassociation, and rounding behavior. Specify an error budget and validate it over the actual domain before considering either.

## Bad

```rust
// A faster approximation is not automatically a replacement for sin():
fn sine(x: f64) -> f64 {
    x - x * x * x / 6.0 + x * x * x * x * x / 120.0
}
```

Declaring a universal winner from one benchmark, or comparing a synchronous iterator to an asynchronous stream without accounting for executor and scheduling costs, is similarly misleading.

## Good

```rust
use std::hint::black_box;

fn sum_iter(values: &[u64]) -> u64 {
    values.iter().copied().filter(|x| x % 2 == 0).sum()
}

fn sum_loop(values: &[u64]) -> u64 {
    let mut total = 0;
    for &value in values {
        if value % 2 == 0 {
            total += value;
        }
    }
    total
}

fn check_equivalence(values: &[u64]) {
    assert_eq!(sum_iter(values), sum_loop(values));
    black_box(sum_iter(black_box(values)));
    black_box(sum_loop(black_box(values)));
}
```

Use Criterion or a comparable harness for repeated, randomized-order measurements with adequate sample sizes; black-box inputs and outputs without hiding the actual optimization opportunity. Keep overflow semantics identical for the selected input domain. Record toolchain, target features, build profile, dataset and confidence intervals. For async comparisons, separately measure actual asynchronous I/O and CPU-only iteration.

## See Also

- [less_slow.rs source](https://github.com/ashvardanian/less_slow.rs/blob/main/less_slow.rs) — original experiments; uses nightly-only coroutine and core-intrinsic features, so it is not a stable-Rust implementation template.
- [Criterion.rs](https://bheisler.github.io/criterion.rs/book/) — statistical benchmarking.
- [Rust Performance Book](https://nnethercote.github.io/perf-book/) — profiling and measurement.
- [`test-criterion-bench`](test-criterion-bench.md) if present in the installed rule set.
