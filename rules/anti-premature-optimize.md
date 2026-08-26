# anti-premature-optimize

> Don't optimize before profiling

## Why It Matters

Optimization has costs: engineering time, extra complexity, portability constraints, and sometimes worse performance on workloads you did not measure. Start with clear code, measure a representative build/workload, then optimize the bottlenecks that matter.

This does not mean “ignore obvious asymptotic problems until production.” Choose sensible algorithms and data structures up front; reserve low-level tuning and added complexity for cases backed by measurements or hard requirements.

## Bad

```rust
// Unsafe bounds-check removal without evidence that bounds checks remain.
fn sum(data: &[i32]) -> i32 {
    unsafe {
        let mut total = 0;
        for i in 0..data.len() {
            total += *data.get_unchecked(i);
        }
        total
    }
}
```

Idiomatic iteration already gives the optimizer a straightforward bounds-check-free shape on common targets, without adding an unsafe invariant.

## Good

```rust
use std::collections::HashMap;

fn sum(data: &[i32]) -> i32 {
    data.iter().copied().sum()
}

fn sum_after_profiling(data: &[i32]) -> i32 {
    // Keep the measured implementation here. This placeholder deliberately
    // remains simple until a benchmark demonstrates a better implementation.
    data.iter().copied().sum()
}

let cache: HashMap<String, u64> = HashMap::new();
assert!(cache.is_empty());
```

If profiling later shows `sum_after_profiling` is important, benchmark candidate implementations on the supported targets and keep the simplest version that meets the requirement.

## Profiling Workflow

```bash
cargo build --release

# Sampling/flamegraph with a representative workload
cargo flamegraph --bin my_app -- --real-args

# Focused benchmarks where a stable microbenchmark is meaningful
cargo bench
```

Then:

1. Identify a material bottleneck.
2. Record a baseline.
3. Change one thing.
4. Measure the new implementation under representative inputs.
5. Keep the complexity only if the improvement is meaningful and robust.

## When Up-Front Optimization Is Justified

Measurement can include constraints known before implementation, not only profiler output. Examples include:

- a protocol or realtime deadline,
- a strict memory budget,
- an algorithm whose asymptotic behavior is obviously unacceptable at the required scale,
- an allocation-free/no-std environment,
- a latency or throughput SLO backed by load estimates.

The point is to connect complexity to evidence or requirements rather than folklore.

## Common Traps

| Speculative change | Better first question |
|--------------------|-----------------------|
| `#[inline(always)]` everywhere | Is call overhead or missed inlining visible in profiles/codegen? |
| unsafe indexing | Does optimized code still contain relevant checks? |
| custom allocator | Are allocations actually material, and which sizes/paths dominate? |
| object pooling | Is allocation/reclamation the bottleneck under concurrency? |
| manual SIMD | Does auto-vectorized code miss the target throughput, and on which CPUs? |
| cache layer | Is recomputation expensive enough to justify invalidation/state complexity? |

## Document Non-Obvious Optimizations

When optimized code is less obvious, leave enough evidence to reevaluate it later:

```rust
/// Uses a lookup table because benchmark `char_class` showed this path is a
/// material parser hotspot on the supported workloads. Keep the benchmark when
/// changing the representation.
static CHAR_CLASS: [u8; 256] = [0; 256];
```

Prefer references to checked-in benchmarks/profiles over timeless numeric claims copied into comments.

## See Also

- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
- [test-criterion-bench](./test-criterion-bench.md) - Benchmarking
- [opt-inline-small](./opt-inline-small.md) - Inline guidelines
