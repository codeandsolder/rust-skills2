# perf-profile-first

> Profile before optimizing

## Why It Matters

Intuition about performance is often wrong. The code you think is slow frequently isn't, while actual bottlenecks hide in unexpected places. Profiling shows you exactly where time is spent, preventing wasted effort on optimizations that don't matter.

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding workload functions -->
```rust
// Optimizing without measuring
fn process(data: &[Item]) -> Vec<Output> {
    // "I bet this clone is slow..."
    let cloned: Vec<_> = data.iter().cloned().collect();
    
    // Actually, 99% of time is spent here:
    cloned.iter().map(|x| expensive_computation(x)).collect()
}

// Over-engineering rarely-called code
#[inline(always)]
fn rarely_called() {
    // This runs once at startup...
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// 1. Profile first
// cargo flamegraph --bin myapp
// cargo instruments -t time --bin myapp (macOS)
// samply record ./target/release/myapp  (cross-platform)

// 2. Find the actual bottleneck
// Flamegraph shows expensive_computation takes 95% of time

// 3. Optimize the hot spot
fn process(data: &[Item]) -> Vec<Output> {
    // Clone is fine - only 1% of time
    let cloned: Vec<_> = data.iter().cloned().collect();
    
    // Focus optimization HERE
    cloned.par_iter()  // Parallelize the expensive part
        .map(|x| expensive_computation(x))
        .collect()
}
```

## Profiling Tools

### samply (Cross-Platform Sampling Profiler, Recommended)

[samply](https://github.com/mstange/samply) is a sampling profiler that outputs to the Firefox Profiler format. It works on Linux, macOS, and Windows with no special kernel modules:

```bash
# Install
cargo install samply

# Profile a binary
samply record ./target/release/myapp -- <args>

# Opens Firefox Profiler UI automatically
# Shows flame graphs, call trees, timeline
```

Advantages: low overhead, works on release builds, native stack walking, no instrumentation needed.

### Flamegraphs (Traditional)

```bash
# Install
cargo install flamegraph

# Profile
cargo flamegraph --bin myapp -- <args>

# Opens flamegraph.svg showing call stacks by time
```

### perf (Linux)

```bash
# Record
perf record -g cargo run --release

# Report
perf report

# Or generate flamegraph
perf script | inferno-collapse-perf | inferno-flamegraph > flamegraph.svg
```

### Instruments (macOS)

```bash
# Install cargo-instruments
cargo install cargo-instruments

# Time profiler
cargo instruments -t time --release

# Allocations profiler
cargo instruments -t alloc --release
```

### CodSpeed CI (Hardware-Counter Benchmarking)

[CodSpeed](https://codspeed.io) provides CI benchmarking using hardware performance counters. It works with Criterion and Divan, measuring instruction counts rather than wall-clock time — eliminating noise from system load:

```toml
# .github/workflows/bench.yml
name: Benchmarks
on: [push]
jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - uses: CodSpeedHQ/action@v3
        with:
          token: ${{ secrets.CODSPEED_TOKEN }}
          run: cargo bench
```

```rust
// bench.rs — works with CodSpeed unchanged
use divan::black_box;

fn main() {
    divan::main();
}

#[divan::bench]
fn compute() -> i32 {
    expensive_computation(black_box(42))
}
```

### cargo-llvm-cov (Coverage-Guided Optimization)

Coverage data helps identify cold/dead code paths. Combined with PGO, it guides inlining and layout decisions:

```bash
# Install
cargo install cargo-llvm-cov

# Generate coverage report
cargo llvm-cov --open

# Use with PGO for production builds
cargo llvm-cov --profile=release
```

### DHAT (Heap Profiling)

```bash
# In your code
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    let _profiler = dhat::Profiler::new_heap();
    // ... your code
}

# Run and get allocation report
cargo run --release
```

### criterion (Micro-benchmarks)

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_my_function(c: &mut Criterion) {
    c.bench_function("my_function", |b| {
        b.iter(|| my_function(black_box(input)))
    });
}

criterion_group!(benches, bench_my_function);
criterion_main!(benches);
```

## Rust 1.90: LLD Default Linker

Since Rust 1.90, `rust-lld` is the default linker on `x86_64-unknown-linux-gnu`. LLD is significantly faster than GNU ld and produces comparable code. If you see linker warnings or errors in older projects, this may be the cause:

```bash
# LLD is now used by default — no configuration needed
cargo build --release

# To revert to GNU ld if needed:
# RUSTFLAGS="-C link-args=-fuse-ld=bfd" cargo build --release
```

## What to Look For

```
Flamegraph Reading:
├── Width = time spent
├── Height = call stack depth
└── Look for:
    ├── Wide bars (time hogs)
    ├── malloc/free (allocation heavy)
    ├── memcpy (copying data)
    └── Unexpected functions taking time
```

## Common Findings

```rust
// Finding: HashMap operations are slow
// Fix: Use FxHashMap or AHashMap for non-crypto hashing

// Finding: String allocation in hot loop
// Fix: Pre-allocate with capacity, use &str

// Finding: Clone in hot path
// Fix: Use references or Cow

// Finding: Bounds checks visible in profile
// Fix: Use iterators instead of indexing

// Finding: Lock contention
// Fix: Reduce critical section, use RwLock, or partition data
```

## Optimization Workflow

```
1. Write correct code first
2. Write benchmarks for hot paths
3. Profile under realistic load
4. Identify actual bottlenecks
5. Optimize ONE thing
6. Measure improvement
7. Repeat if needed
```

## Evidence: Rust Performance Book

> "The biggest performance improvements often come from changes to algorithms or data structures, rather than low-level optimizations."

> "It is worth understanding which Rust data structures and operations cause allocations, because avoiding them can greatly improve performance."

## See Also

- [opt-lto-release](opt-lto-release.md) - Enable LTO for release builds
- [test-criterion-bench](test-criterion-bench.md) - Use criterion for benchmarking
- [perf-release-profile](./perf-release-profile.md) - Release profile settings
- [anti-premature-optimize](anti-premature-optimize.md) - Don't optimize without data
