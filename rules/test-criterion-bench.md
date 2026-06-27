# test-criterion-bench

> Use `criterion` for benchmarking (or `divan` for simpler workflows)

## Why It Matters

Benchmarking requires statistical rigor — warmup, multiple iterations, outlier detection. `criterion` is the standard for statistical CI benchmarks. For simpler use cases, `divan` (4.6M+ downloads, v0.1.21) provides a zero-config attribute-based API. For instruction-level analysis, use `iai-callgrind`.

## Criterion Setup

```toml
# Cargo.toml
[dev-dependencies]
criterion = "0.5"

[[bench]]
name = "my_benchmark"
harness = false
```

## Divan (Simpler Alternative)

```rust
// benches/my_benchmark.rs
use divan::black_box;

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        n => fibonacci(n - 1) + fibonacci(n - 2),
    }
}

fn main() {
    divan::main();
}

#[divan::bench]
fn fib_20() -> u64 {
    fibonacci(black_box(20))
}

// Parameterized
#[divan::bench(args = [10, 20, 30])]
fn fib_n(n: u64) -> u64 {
    fibonacci(black_box(n))
}

// With max time
#[divan::bench(max_time = 5)]
fn heavy_computation() -> u64 {
    compute(black_box(1000))
}
```

```toml
# Cargo.toml
[dev-dependencies]
divan = "0.1"

[[bench]]
name = "my_benchmark"
harness = false
```

## iai-callgrind (Instruction-Level)

```rust
// benches/iai_bench.rs
use iai_callgrind::library_benchmark;

#[library_benchmark]
#[bench::small("a")]
#[bench::large("a".repeat(1000))]
fn bench_strlen(input: &str) -> usize {
    input.len()
}

fn main() {
    iai_callgrind::library_benchmark_group!(
        name = my_group;
        benchmarks = bench_strlen
    ).main();
}
```

```toml
# Cargo.toml
[dev-dependencies]
iai-callgrind = "0.13"

[[bench]]
name = "iai_bench"
harness = false
```

## CodSpeed CI Integration

```yaml
# .github/workflows/bench.yml
- name: Run benchmarks with CodSpeed
  uses: CodSpeedHQ/action@v2
  with:
    run: cargo bench
    token: ${{ secrets.CODSPEED_TOKEN }}
```

CodSpeed works with both Criterion and Divan, providing hosted historical tracking, regression detection, and PR comments.

## Basic Criterion Benchmark

## Basic Benchmark

```rust
// benches/my_benchmark.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        n => fibonacci(n - 1) + fibonacci(n - 2),
    }
}

fn bench_fibonacci(c: &mut Criterion) {
    c.bench_function("fib 20", |b| {
        b.iter(|| fibonacci(black_box(20)))
    });
}

criterion_group!(benches, bench_fibonacci);
criterion_main!(benches);
```

## black_box is Critical

```rust
// BAD: Compiler may optimize away the computation
b.iter(|| fibonacci(20));  // Result unused, might be eliminated

// GOOD: black_box prevents optimization
b.iter(|| fibonacci(black_box(20)));

// Also wrap the result if needed
b.iter(|| black_box(fibonacci(black_box(20))));
```

## Comparing Implementations

```rust
fn bench_comparison(c: &mut Criterion) {
    let mut group = c.benchmark_group("String concat");
    
    let data = "hello";
    
    group.bench_function("format!", |b| {
        b.iter(|| format!("{}{}", black_box(data), " world"))
    });
    
    group.bench_function("push_str", |b| {
        b.iter(|| {
            let mut s = String::from(black_box(data));
            s.push_str(" world");
            s
        })
    });
    
    group.bench_function("concat", |b| {
        b.iter(|| [black_box(data), " world"].concat())
    });
    
    group.finish();
}
```

## Parameterized Benchmarks

```rust
fn bench_vec_push(c: &mut Criterion) {
    let mut group = c.benchmark_group("Vec::push");
    
    for size in [100, 1000, 10000].iter() {
        group.bench_with_input(
            BenchmarkId::from_parameter(size),
            size,
            |b, &size| {
                b.iter(|| {
                    let mut v = Vec::new();
                    for i in 0..size {
                        v.push(black_box(i));
                    }
                    v
                });
            },
        );
    }
    
    group.finish();
}
```

## Throughput Measurement

```rust
use criterion::Throughput;

fn bench_parse(c: &mut Criterion) {
    let input = "a]ong string to parse...";
    
    let mut group = c.benchmark_group("Parser");
    group.throughput(Throughput::Bytes(input.len() as u64));
    
    group.bench_function("parse", |b| {
        b.iter(|| parse(black_box(input)))
    });
    
    group.finish();
}
```

## Running Benchmarks

```bash
# Run all benchmarks
cargo bench

# Run specific benchmark
cargo bench -- fib

# Save baseline for comparison
cargo bench -- --save-baseline main

# Compare against baseline
cargo bench -- --baseline main
```

## Evidence from tokio

```rust
// https://github.com/tokio-rs/tokio/blob/master/benches/sync_mpsc.rs
use criterion::{criterion_group, criterion_main, Criterion};

fn send_data<T: Default, const SIZE: usize>(
    g: &mut BenchmarkGroup<WallTime>, 
    prefix: &str
) {
    let rt = rt();
    g.bench_function(format!("{prefix}_{SIZE}"), |b| {
        b.iter(|| {
            let (tx, mut rx) = mpsc::channel::<T>(SIZE);
            rt.block_on(tx.send(T::default())).unwrap();
            rt.block_on(rx.recv()).unwrap();
        })
    });
}
```

## See Also

- [perf-profile-first](perf-profile-first.md) - Profile before optimizing
- [perf-black-box-bench](perf-black-box-bench.md) - Use black_box in benchmarks
- [Divan](https://github.com/nvzqz/divan) — Simpler benchmarking
- [CodSpeed](https://codspeed.io/docs/guides/how-to-benchmark-rust-with-divan) — CI benchmark tracking
- [iai-callgrind](https://crates.io/crates/iai-callgrind) — Instruction-count benchmarks
