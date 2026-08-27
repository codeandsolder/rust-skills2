# opt-target-cpu

> Tune `target-cpu` only for deployment CPUs you actually control, and use explicit runtime dispatch for portable binaries

## Why It Matters

`rustc` normally targets the baseline implied by the selected target triple. Passing `-C target-cpu=...` can enable additional instructions and tune scheduling for a more specific processor, but it also changes the minimum CPU requirements of the generated code.

`target-cpu=native` means **the CPU running the compiler**. It is useful for local workloads and controlled deployment, but it is a poor default for redistributable binaries because the build machine may support instructions that users' machines do not.

Likewise, `x86-64-v3` is a useful named x86-64 feature level when your deployment fleet satisfies it; it is not a universal “modern PC” baseline and should not be recommended by year-of-manufacture folklore.

## Local or Homogeneous Deployment

For a binary that will run on the build machine or an equivalent fleet:

```bash
RUSTFLAGS="-C target-cpu=native" cargo build --release
```

For a known target CPU, use a CPU name supported by the toolchain:

```bash
rustc --print target-cpus --target x86_64-unknown-linux-gnu
RUSTFLAGS="-C target-cpu=x86-64-v3" cargo build --release
```

Treat the chosen CPU/features as part of the deployment contract. Test the produced binary on the oldest supported machine or image.

## Cargo Configuration

Target-specific rustflags belong in `.cargo/config.toml` under a real target triple or target cfg expression:

```toml
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "target-cpu=x86-64-v3"]
```

Do not invent nested target names such as `target.x86_64-unknown-linux-gnu.deployment`; Cargo does not interpret an arbitrary suffix as a deployment profile.

For artifacts with different CPU requirements, prefer separate build invocations/config files, explicit environment flags, or separate packages/pipelines so it is obvious which binary has which minimum CPU.

## Portable Binary: Runtime Feature Detection

When one binary must run on CPUs with different features, keep a baseline implementation and dispatch to specialized functions only after checking support.

On x86/x86-64, `is_x86_feature_detected!` performs runtime detection. A `#[target_feature]` function still carries a feature precondition: runtime detection does not magically make an ordinary safe call site feature-enabled.

```rust
#[cfg(target_arch = "x86_64")]
fn sum_bytes(data: &[u8]) -> u64 {
    if std::is_x86_feature_detected!("avx2") {
        // SAFETY: runtime detection above established that AVX2 is available.
        unsafe { sum_bytes_avx2(data) }
    } else {
        sum_bytes_generic(data)
    }
}

#[cfg(target_arch = "x86_64")]
fn sum_bytes_generic(data: &[u8]) -> u64 {
    data.iter().map(|&value| u64::from(value)).sum()
}

#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
unsafe fn sum_bytes_avx2(data: &[u8]) -> u64 {
    // A real implementation may use AVX2 intrinsics or code that benefits
    // from compiling this function with AVX2 enabled.
    data.iter().map(|&value| u64::from(value)).sum()
}

#[cfg(target_arch = "x86_64")]
fn main() {
    assert_eq!(sum_bytes(&[1, 2, 3]), 6);
}

#[cfg(not(target_arch = "x86_64"))]
fn main() {}
```

The Rust Reference also permits safe `#[target_feature]` functions in some positions, but such a function can only be **safely** called from a context that already enables all of its required target features. An ordinary runtime `if` does not change that static calling context. Using a small unsafe dispatch boundary after successful runtime detection keeps the precondition explicit.

## Whole-Binary Features and Function-Level Features Are Different

`-C target-cpu` / `-C target-feature` affect code generation for compilation units. `#[target_feature]` creates specialized functions inside a binary. Choose based on the compatibility requirement:

- homogeneous fleet: whole-program `target-cpu` may be simplest;
- heterogeneous fleet: baseline binary plus runtime dispatch is often safer;
- library: be especially careful not to raise the caller's CPU requirement unexpectedly.

Target-feature combinations can also interact with ABI and precompiled dependencies. The rustc documentation treats target-feature selection as something that requires care; do not assume arbitrary feature disabling/enabling is harmless merely because LLVM accepts the flag.

## Do Not Promise Specific Code Generation

Enabling AVX2 does not guarantee that a scalar iterator becomes a four-lane vector loop. Auto-vectorization depends on the operation, aliasing, optimization level, LLVM, surrounding code, and target.

```rust
fn sum_squares(values: &[f64]) -> f64 {
    values.iter().map(|value| value * value).sum()
}

fn main() {
    assert_eq!(sum_squares(&[2.0, 3.0]), 13.0);
}
```

Use benchmarks and assembly/IR inspection when the reason for changing `target-cpu` is a specific hot loop.

## LTO and Compiler-Version Regressions

Do not turn a particular compiler issue (for example, an LTO slowdown on one target level) into a permanent universal rule such as “never use fat LTO with x86-64-v3.” Compiler regressions are version-specific. Pin/upgrade the toolchain or choose LTO settings based on current measurements and build-time constraints.

## Practical Guidance

- Use `target-cpu=native` for local or tightly controlled deployment, not generic distribution.
- Pick `x86-64-v2/v3/v4` or named CPUs only when the supported fleet is known to meet that requirement.
- Keep a baseline path when distributing one binary across heterogeneous CPUs.
- Runtime-detect features before crossing into a specialized `#[target_feature]` implementation.
- Keep the feature-safety boundary explicit; detection alone does not alter the static call context.
- Verify both compatibility and performance on representative deployment hardware.

## See Also

- [opt-lto-release](./opt-lto-release.md) - LTO trade-offs
- [opt-simd-portable](./opt-simd-portable.md) - SIMD approaches
- [perf-profile-first](./perf-profile-first.md) - Measure the real bottleneck
