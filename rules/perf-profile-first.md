# perf-profile-first

> Measure representative workloads before choosing an optimization, then measure again after the change.

## Why It Matters

Performance work is an experiment. Source-code intuition can identify candidates, but it cannot tell you which cost dominates a real workload, how often a path runs, or whether an optimization improves end-to-end behavior.

A useful workflow separates three questions:

1. **Where is time/memory/latency going?** — profile the representative application or service.
2. **Can I reproduce the hot operation?** — benchmark the relevant operation with realistic inputs when a microbenchmark is useful.
3. **Did the change help the metric that matters without unacceptable regressions?** — compare before/after under the same conditions.

## Bad: Optimize the Visually Suspicious Line First

<!-- rust-check: compile -->
```rust
#[derive(Clone)]
struct Item(u64);

fn expensive_computation(item: &Item) -> u64 {
    (0..1_000).fold(item.0, |value, n| value.wrapping_mul(31).wrapping_add(n))
}

fn process(data: &[Item]) -> Vec<u64> {
    // It is easy to fixate on this allocation/clone because it is visible.
    let cloned = data.to_vec();

    // But without measurement we do not know which cost dominates.
    cloned.iter().map(expensive_computation).collect()
}
```

The clone may matter. The computation may matter. Cache behavior, allocation, I/O around this function, or something outside it may matter more. The source alone does not establish the bottleneck.

## Good: Make the Optimization Follow Evidence

<!-- rust-check: compile -->
```rust
#[derive(Clone)]
struct Item(u64);

fn expensive_computation(item: &Item) -> u64 {
    (0..1_000).fold(item.0, |value, n| value.wrapping_mul(31).wrapping_add(n))
}

fn process(data: &[Item]) -> Vec<u64> {
    // Suppose profiling/benchmarking showed the clone was measurable and
    // unnecessary. Remove exactly that work, then remeasure.
    data.iter().map(expensive_computation).collect()
}
```

The comment is intentionally conditional. Do not invent percentages such as “this was 95% of runtime” unless a real measurement produced them.

## Start With a Representative Build and Workload

Profile the configuration users actually care about. For throughput/latency code that usually means a release-like optimized build and realistic input sizes, concurrency, feature flags, and data distributions.

Debug builds can be useful for correctness but can produce radically different performance shapes. Conversely, a tiny synthetic input may hide allocation or cache costs that dominate production.

Useful profiler categories include:

- sampling CPU profilers (for example `perf`, Instruments, samply, or platform equivalents),
- allocation/heap profilers,
- tracing and application metrics for waiting/queueing/I/O,
- hardware performance counters when low-level CPU behavior is the question.

The tool is secondary to collecting representative evidence.

## Microbenchmarks Answer Narrow Questions

Use a benchmark when you need stable comparison of a small operation, not as a substitute for application profiling.

<!-- rust-check: compile -->
```rust
use criterion::Criterion;
use std::hint::black_box;

fn checksum(data: &[u8]) -> u64 {
    data.iter().map(|&byte| byte as u64).sum()
}

fn bench_checksum(c: &mut Criterion) {
    let data = vec![7_u8; 4096];

    c.bench_function("checksum_4k", |b| {
        b.iter(|| black_box(checksum(black_box(&data))))
    });
}
```

Choose benchmark boundaries carefully. If allocation or parsing is part of the production operation, moving it outside the measured region can create a misleading win.

## Prefer Algorithmic and Architectural Wins When Evidence Points There

Low-level hints are often much smaller than avoiding unnecessary work.

Examples of high-leverage questions:

- Can the algorithm avoid an O(n²) scan?
- Can repeated parsing/hashing/allocation be reused or eliminated?
- Is work being performed that the caller never needs?
- Is lock contention or queueing dominating compute time?
- Is I/O batching or data layout the real limit?

Do not automatically replace `HashMap` hashers, add `unsafe`, force inlining, or parallelize merely because those techniques can be faster in some workloads. Each changes tradeoffs and needs evidence.

## Optimize One Explainable Thing at a Time

A disciplined loop is:

1. record a baseline and environment,
2. identify a bottleneck or hypothesis,
3. make one focused change,
4. rerun the same measurement,
5. check relevant guardrails (memory, tail latency, binary size, correctness, CPU use, etc.),
6. keep, revise, or revert based on the result.

Small isolated changes make regressions and false wins easier to diagnose.

## Be Careful With Profiler Percentages

A profile percentage is relative to the sampled run. If you optimize one function, another function's percentage can rise even if its absolute time stays unchanged. Compare absolute end-to-end metrics as well as profile shape.

Sampling also has noise and resolution limits. Very short functions may be attributed to callers, inlined into other frames, or too small to sample reliably. Use assembly/counters/microbenchmarks only when the question requires that level of detail.

## Preserve Reproducibility

For benchmark comparisons, record enough context to make the result meaningful:

- commit/build flags and target,
- relevant CPU/platform information,
- input/data set,
- feature flags and concurrency,
- benchmark/profiler command,
- repeated samples where noise matters.

Do not treat one wall-clock number from a busy development machine as a universal performance fact.

## A Performance Improvement Is a Tradeoff Decision

A faster hot path may increase memory, binary size, compile time, code complexity, or worst-case latency. Decide which metrics are guardrails before optimizing.

For example, `#[inline(always)]` may improve a microbenchmark while increasing code size; a cache may reduce CPU while increasing memory; parallelism may improve throughput while worsening single-request latency or contention.

## Decision Guide

| Question | Evidence to gather |
|---|---|
| Where is CPU time spent? | application profile |
| Does this small implementation change help? | focused benchmark |
| Is allocation the problem? | allocation profile/counters |
| Is waiting/queueing the problem? | tracing/latency/queue metrics |
| Did the optimization help users? | end-to-end metric under representative load |
| Did it create regressions? | predefined guardrails + tests |

## See Also

- [perf-black-box-bench](./perf-black-box-bench.md) - Avoid optimizer artifacts in microbenchmarks
- [perf-release-profile](./perf-release-profile.md) - Release optimization settings
- [anti-premature-optimize](./anti-premature-optimize.md) - Avoid unsupported tuning
- [opt-inline-always-rare](./opt-inline-always-rare.md) - Measure forced-inline hints
