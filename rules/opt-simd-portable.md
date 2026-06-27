# opt-simd-portable

> Use portable SIMD for vectorized operations across architectures

## Why It Matters

SIMD (Single Instruction, Multiple Data) processes multiple values per instruction—4x, 8x, or more speedup for suitable algorithms. Rust's `std::simd` remains nightly-only, but stable alternatives (`wide`, `pulp`, `safe_arch`) and safe `#[target_feature]` (Rust 1.86+) now provide robust portable SIMD for stable Rust.

## Autovectorization (Stable, zero-effort)

```rust
// LLVM often vectorizes simple patterns automatically
fn sum(data: &[f32]) -> f32 {
    data.iter().sum()  // May vectorize to SIMD
}

fn add_arrays(a: &[f32], b: &[f32], out: &mut [f32]) {
    for ((x, y), o) in a.iter().zip(b).zip(out.iter_mut()) {
        *o = x + y;  // Often vectorizes
    }
}

// Help autovectorization:
// 1. Use iterators over indexing
// 2. Avoid early exits in loops
// 3. Use chunks_exact for aligned access
// 4. Prefer f32/f64/i32/i64 types (wider vectors)
```

## wide Crate (Stable)

The `wide` crate provides fixed-width SIMD types on stable Rust:

```rust
use wide::*;

fn process_simd(data: &mut [f32]) {
    // Process 8 floats at a time
    for chunk in data.chunks_exact_mut(8) {
        let v = f32x8::from(chunk);
        let result = v * f32x8::splat(2.0) + f32x8::splat(1.0);
        chunk.copy_from_slice(&result.to_array());
    }
}

fn blend_images(a: &[u8], b: &[u8], alpha: f32, out: &mut [u8]) {
    let alpha_v = f32x8::splat(alpha);
    let one_minus = f32x8::splat(1.0 - alpha);
    
    for ((a_chunk, b_chunk), out_chunk) in 
        a.chunks_exact(8).zip(b.chunks_exact(8)).zip(out.chunks_exact_mut(8)) 
    {
        let av = f32x8::from([
            a_chunk[0] as f32, a_chunk[1] as f32, /* ... */
        ]);
        let bv = f32x8::from([
            b_chunk[0] as f32, b_chunk[1] as f32, /* ... */
        ]);
        
        let result = av * one_minus + bv * alpha_v;
        // Convert back to u8...
    }
}
```

## pulp Crate (Stable Multiversioning)

The `pulp` crate provides architecture-adaptive SIMD dispatch on stable Rust:

```rust
use pulp::Arch;

fn sum_f32(data: &[f32]) -> f32 {
    // Automatically picks SSE, AVX2, or AVX-512 at runtime
    pulp::Arch::new().dispatch(|simd| {
        let (prefix, middle, suffix) = simd.as_simd_chunks(data);

        let mut sum = simd.splat(0.0);
        for &chunk in middle {
            sum = simd.add(sum, simd.splat(chunk.iter().copied().sum::<f32>()));
        }
        let sum_scalar: f32 = simd.reduce_sum(sum);
        sum_scalar + prefix.iter().sum::<f32>() + suffix.iter().sum::<f32>()
    })
}
```

## safe_arch Crate (Stable)

The `safe_arch` crate provides safe wrappers around platform intrinsics:

```rust
use safe_arch::*;

fn dot_product_sse4(a: &[f32; 4], b: &[f32; 4]) -> f32 {
    // Safe wrappers around SSE4.1 intrinsics
    let va = m128::from(*a);
    let vb = m128::from(*b);
    let prod = mul_m128(va, vb);
    // Horizontal add
    hadd_m128(prod).to_array()[0]
}
```

## Safe #[target_feature] (Rust 1.86+) and Safe Intrinsics (Rust 1.87+)

Since Rust 1.86, `#[target_feature]` works on safe `fn` (not just `unsafe fn`). Since Rust 1.87, most `std::arch` intrinsics without pointer arguments are callable from safe code:

```rust
// Since Rust 1.86: #[target_feature] on safe fn
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
fn sum_avx2_safe(data: &[f32]) -> f32 {
    // Since Rust 1.87: many intrinsics without pointer args are safe
    let mut sum = std::arch::x86_64::_mm256_setzero_ps();
    
    for chunk in data.chunks_exact(8) {
        let v = unsafe {
            // _mm256_loadu_ps still requires unsafe (pointer arg)
            std::arch::x86_64::_mm256_loadu_ps(chunk.as_ptr())
        };
        sum = std::arch::x86_64::_mm256_add_ps(sum, v);
    }
    
    // ... horizontal reduction
    0.0
}

// Runtime feature detection (stable)
fn sum_dispatch(data: &[f32]) -> f32 {
    #[cfg(target_arch = "x86_64")]
    {
        if std::is_x86_feature_detected!("avx2") {
            return sum_avx2_safe(data);  // No unsafe block needed
        }
    }
    data.iter().sum()  // Fallback
}
```

## Choosing an Approach

| Approach | Stability | Portability | Control | Complexity |
|----------|-----------|-------------|---------|------------|
| Autovectorization | Stable | Excellent | Low | Zero |
| `wide` crate | Stable | Good | Medium | Low |
| `pulp` crate | Stable | Excellent | Medium | Medium |
| `safe_arch` crate | Stable | None (platform specific) | High | Medium |
| Safe `#[target_feature]` | Stable (1.86+) | None | Maximum | High |
| `std::simd` | Nightly | Excellent | High | Medium |

## When to Choose What

- **Autovectorization** — first choice, always measure
- **`wide`** — simple fixed-width SIMD on stable, single architecture
- **`pulp`** — best portable SIMD on stable with runtime dispatch
- **`safe_arch`** — need platform-specific SIMD safely
- **`#[target_feature]`** — maximum control, willing to write per-platform code

## See Also

- [opt-target-cpu](./opt-target-cpu.md) - Enable SIMD features
- [opt-bounds-check](./opt-bounds-check.md) - Unchecked access for SIMD
- [perf-profile-first](./perf-profile-first.md) - Identify vectorization opportunities
