# opt-inline-always-rare

> Use `#[inline(always)]` sparingly—only for critical hot paths proven by profiling

## Why It Matters

`#[inline(always)]` forces the compiler to inline a function regardless of heuristics. Overuse increases binary size, hurts instruction cache, and can slow down code. The compiler is usually smarter about inlining than humans. Reserve this for measured hot paths where benchmarks prove a benefit.

## Bad

<!-- rust-check: fragment; reason=method anti-pattern is extracted without its surrounding impl -->
```rust
// Annotating everything - trusting intuition over data
#[inline(always)]
pub fn get_name(&self) -> &str {
    &self.name
}

#[inline(always)]
pub fn calculate_tax(amount: f64) -> f64 {
    amount * 0.1
}

#[inline(always)]
fn helper(x: i32) -> i32 {
    x + 1
}

// Result: bloated binary, poor cache utilization
```

## Good

<!-- rust-check: fragment; reason=extraction artifact: wrapper/context -->
```rust
// Let compiler decide for most functions
pub fn get_name(&self) -> &str {
    &self.name
}

pub fn calculate_tax(amount: f64) -> f64 {
    amount * 0.1
}

// Only force inline for proven hot paths
impl Hasher for MyHasher {
    // Hasher::write is called millions of times in tight loops
    // Profiling showed 15% improvement from forced inlining
    #[inline(always)]
    fn write(&mut self, bytes: &[u8]) {
        // Very small, very hot
        self.state = self.state.wrapping_add(bytes.len() as u64);
    }
}
```

## When #[inline(always)] Helps

```rust
// ✅ Tiny functions in hot inner loops
#[inline(always)]
fn fast_hash(a: u64, b: u64) -> u64 {
    a.wrapping_mul(b).wrapping_add(a)
}

// ✅ Generic functions that benefit from monomorphization
#[inline(always)]
fn swap<T>(a: &mut T, b: &mut T) {
    std::mem::swap(a, b);
}

// ✅ Iterator adapters and closures
#[inline(always)]
fn apply<T, F: Fn(T) -> T>(f: F, x: T) -> T {
    f(x)
}

// ✅ SIMD/vectorization helpers
#[inline(always)]
fn add_simd(a: &[f32], b: &[f32], out: &mut [f32]) {
    // ...
}
```

## Inline Variants

```rust
// #[inline] - hint to inline, compiler may ignore
#[inline]
fn suggested_inline(x: i32) -> i32 { x + 1 }

// #[inline(always)] - force inline (almost always)
#[inline(always)]
fn force_inline(x: i32) -> i32 { x + 1 }

// #[inline(never)] - prevent inlining (for profiling, code size)
#[inline(never)]
fn no_inline(x: i32) -> i32 { x + 1 }

// No annotation - compiler decides based on heuristics
fn compiler_decides(x: i32) -> i32 { x + 1 }
```

## Measuring Inline Impact

```rust
// Use criterion to benchmark
use criterion::{criterion_group, criterion_main, Criterion};

fn bench_with_inline(c: &mut Criterion) {
    c.bench_function("hot_path_inline", |b| {
        b.iter(|| hot_loop())
    });
}

// Compare binary sizes
// cargo bloat --release --crates

// Check if function was inlined
// cargo show-asm --rust my_crate::hot_function
```

## Generic Functions

```rust
// Generic functions across crate boundaries often need #[inline]
// Because the generic code is compiled in the calling crate

// In library crate:
#[inline]  // Allow inlining in downstream crates
pub fn generic_function<T: Display>(x: T) {
    println!("{}", x);
}

// Without #[inline], the generic function can't be inlined
// across crate boundaries even if beneficial
```

## Cautions

```rust
// DON'T combine #[cold] with #[inline(always)] — they conflict.
// #[cold] discourages inlining; #[inline(always)] forces it.
// Rust 1.80+ may warn about this combination.
#[cold]
#[inline(always)]  // BAD: contradictory
fn cold_but_inlined() {
    // ...
}

// DON'T assume inlining always helps - measure!
// Sometimes the compiler makes better decisions
```

## See Also

- [opt-inline-small](./opt-inline-small.md) - Regular inline for small functions
- [opt-inline-never-cold](./opt-inline-never-cold.md) - Preventing inlining
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
