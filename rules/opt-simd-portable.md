# opt-simd-portable

> Start with autovectorization; use stable SIMD crates or carefully dispatched `#[target_feature]` code when measurement justifies it.

## Why It Matters

SIMD (Single Instruction, Multiple Data) can process several values per instruction and substantially speed up suitable workloads. Rust's `std::simd` remains nightly-only, while stable crates such as `wide`, `pulp`, and `safe_arch` provide alternatives. Stable `#[target_feature]` support gives low-level control, but runtime detection does **not** make a call to a feature-enabled function safe by itself.

## Autovectorization (Stable)

```rust
fn sum(data: &[f32]) -> f32 {
    data.iter().sum()
}

fn add_arrays(a: &[f32], b: &[f32], out: &mut [f32]) {
    for ((x, y), o) in a.iter().zip(b).zip(out.iter_mut()) {
        *o = x + y;
    }
}
```

Prefer simple loops/iterators and measure generated code before adding explicit SIMD.

## `wide` Crate (Stable)

```rust
use wide::*;

fn process_simd(data: &mut [f32]) {
    for chunk in data.chunks_exact_mut(8) {
        let v = f32x8::from(chunk);
        let result = v * f32x8::splat(2.0) + f32x8::splat(1.0);
        chunk.copy_from_slice(&result.to_array());
    }
}
```

## `pulp` Crate (Stable Multiversioning)

Use `pulp` when you want architecture-adaptive dispatch without hand-writing every target-specific boundary. Follow the crate's current API rather than copying version-specific examples blindly.

## `safe_arch` Crate (Stable)

`safe_arch` wraps many platform intrinsics in safe APIs, but the code remains architecture-specific and still needs appropriate dispatch when the binary can run on CPUs with different feature sets.

## `#[target_feature]` Runtime Dispatch

A function with `#[target_feature(enable = "...")]` may be written as a safe `fn`, but calling it from code that does not itself enable that feature is still an unsafe operation. Runtime feature detection is how you justify that unsafe call.

```rust
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
fn sum_avx2(data: &[f32]) -> f32 {
    let mut sum = std::arch::x86_64::_mm256_setzero_ps();

    for chunk in data.chunks_exact(8) {
        let v = unsafe {
            // Pointer-taking loads still require the caller to establish
            // pointer validity for the intrinsic.
            std::arch::x86_64::_mm256_loadu_ps(chunk.as_ptr())
        };
        sum = std::arch::x86_64::_mm256_add_ps(sum, v);
    }

    // Horizontal reduction omitted for brevity.
    0.0
}

fn sum_dispatch(data: &[f32]) -> f32 {
    #[cfg(target_arch = "x86_64")]
    {
        if std::is_x86_feature_detected!("avx2") {
            // SAFETY: runtime feature detection established that AVX2 is
            // available on the current CPU before entering this function.
            return unsafe { sum_avx2(data) };
        }
    }

    data.iter().sum()
}
```

The unsafe block belongs at the dispatch boundary so the CPU-feature invariant is explicit and auditable.

## Choosing an Approach

| Approach | Stability | Portability | Control | Complexity |
|----------|-----------|-------------|---------|------------|
| Autovectorization | Stable | Excellent | Low | Low |
| `wide` | Stable | Good | Medium | Low |
| `pulp` | Stable | Excellent | Medium | Medium |
| `safe_arch` | Stable | Platform-specific | High | Medium |
| `#[target_feature]` | Stable | Platform-specific | Maximum | High |
| `std::simd` | Nightly | Excellent | High | Medium |

## When to Choose What

- **Autovectorization** — default first choice; inspect/benchmark before escalating.
- **`wide`** — simple fixed-width explicit SIMD on stable Rust.
- **`pulp`** — portable runtime dispatch and multiversioning on stable Rust.
- **`safe_arch`** — platform-specific intrinsics with safer wrappers.
- **`#[target_feature]`** — maximum control when you can maintain explicit feature detection and unsafe dispatch boundaries.

## See Also

- [opt-target-cpu](./opt-target-cpu.md) - Enable SIMD features
- [opt-bounds-check](./opt-bounds-check.md) - Unchecked access for SIMD
- [perf-profile-first](./perf-profile-first.md) - Identify vectorization opportunities
