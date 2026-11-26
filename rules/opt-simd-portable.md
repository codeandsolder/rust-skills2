# opt-simd-portable

> Treat portable SIMD as a semantic abstraction, not a speed guarantee: preserve scalar behavior, use safe vector memory operations, dispatch CPU-specific kernels correctly, and verify code generation and measured performance.

## Why It Matters

SIMD can speed up independent data-parallel work, but wrong overflow, tails, mask evaluation, memory alignment, or CPU dispatch can silently corrupt data or fail only on older machines. Review semantics and target portability before optimizing.

## Scope and Status (Rust 1.100 stable; 1.102.0-nightly, November 2026)

There are **three distinct meanings** of SIMD portability:

1. **Source portability:** the same source compiles for x86-64, AArch64, ARM, WebAssembly, and scalar targets.
2. **Semantic portability:** lane operations have consistent documented results (subject to explicitly documented floating-point exceptions).
3. **Performance portability:** the same algorithm is fast on each target. **No portable SIMD API guarantees this.** A wide type may be split, scalarized, or lowered to several instructions; a narrow type may underutilize the hardware.

As of Rust **1.100 stable and 1.102.0-nightly** (2026-11-21 compiler commit), `core::simd` and `std::simd` are **unstable**, requiring nightly `#![feature(portable_simd)]` ([tracking issue #86656](https://github.com/rust-lang/rust/issues/86656)). Do not imply that `std::simd` is stabilized merely because rustdoc displays it on the stable documentation website. `std::simd` adds `StdFloat` support for some math functions; `core::simd` can be used in `no_std` projects on nightly.

On stable Rust, choose among auto-vectorization, target-specific `core::arch`/`std::arch` intrinsics, and maintained crates such as `wide`, `pulp`, or `safe_arch`. Match the crate's **actual version, CPU requirements, and architecture support**; these crates do not all provide the same form of portability.

| Approach | Baseline | Source portability | Control / tradeoff |
| --- | --- | --- | --- |
| Scalar loops / auto-vectorization | Stable | Excellent | Lowest maintenance; code generation is heuristic |
| `wide` | Stable crate | Portable abstraction with fallbacks | Fixed vectors; not the same API as `std::simd` |
| `pulp` | Stable crate | Architecture-adaptive abstraction | Version-specific dispatch/instruction-set model |
| `safe_arch` | Stable crate | Architecture-specific | Safe wrappers around selected intrinsics, not automatic multiversioning |
| `core::arch` + `#[target_feature]` | Stable | Separate per-architecture kernels | Exact ISA control; dispatch and memory contracts matter |
| `core::simd` / `std::simd` | Nightly | Broad, including scalar targets | Uniform lane model; not stable public API |

**Decision rule:** prototype the simplest correct scalar kernel; profile and inspect optimized code; use explicit vectors when compiler auto-vectorization misses a meaningful opportunity; add architecture-specific specializations only for demonstrated benefits. If nightly is acceptable for the project, `std::simd` is a reasonable explicit-vector choice—not a universal default.

## First: Shape Scalar Code for Autovectorization

Auto-vectorization is not defeated by indexing *as such*, nor guaranteed by iterators. The important properties are independence between iterations, provable bounds, useful data dependencies, and the optimizer's ability to see through abstractions.


```rust
fn add_bias(input: &[u32], output: &mut [u32], bias: u32) {
    for (source, destination) in input.iter().zip(output.iter_mut()) {
        *destination = source.wrapping_add(bias);
    }
}
```

The `zip` contract processes `min(input.len(), output.len())` elements. If the API requires equal lengths, check that invariant explicitly before the loop; otherwise a SIMD rewrite must preserve the shorter-length behavior.

Before writing intrinsics, examine:

- Data dependencies (prefix sums, carried state, loop-carried aliases), independent lanes, and whether branches can become predicates.
- Structure-of-arrays versus array-of-structures, contiguous versus strided access, alignment, and working-set size.
- Arithmetic semantics: overflow, floating-point association, saturation, conversion, and exactness.
- Existing optimized libraries (`memchr`, codecs, compression, BLAS, parsers) that already dispatch among vector kernels.

A favorable `-C target-cpu` may enable autovectorization, but never use `target-cpu=native` for a redistributable binary unless the supported deployment CPUs actually match.

## The `Simd<T, N>` Model

`Simd<T, N>` is conceptually a vector of `N` elements with **element-wise** arithmetic. `N` is a compile-time lane count; the current implementation supports nonzero counts up to 64. It is **not** the number of physical hardware lanes, nor a promise about registers or instructions. Use the actual compiler/API constraints rather than assuming every historical lane-count alias exists.

- `Simd::splat(value)` broadcasts a scalar; `Simd::from_array` / `to_array` move values to and from arrays; `as_array` can expose a reference without making a layout assumption.
- `Simd::from_slice(slice)` reads the first `N` elements and **panics** if there are too few; `copy_to_slice` has the symmetric precondition.
- `load_or_default` / `load_or` safely fill missing contiguous lanes; `load_select` variants combine bounds and masks. A masked-out lane is not read by a *masked load*.
- `Mask` represents a lane-wise boolean; `SimdPartialEq`/`SimdPartialOrd` construct masks and `mask.select(a, b)` chooses elements. `any`, `all`, `to_bitmask`, and `from_bitmask` support predicates and control flow.
- `SimdInt` / `SimdUint` offer reductions, bit operations, saturating arithmetic, and conversions. `SimdFloat` offers floating-point reductions, comparisons, min/max, classification and conversions.
- `simd_swizzle!`, `reverse`, `interleave`, `deinterleave`, `rotate_elements_*`, `shift_elements_*`, and `swizzle_dyn` reorder lanes; their costs vary sharply by ISA and whether indices are compile-time constants.
- `gather_*` / `scatter*` support indexed memory; do not assume they become one gather/scatter machine instruction or outperform contiguous accesses.

The portable SIMD prelude imports common comparison and arithmetic traits. When a method is not in scope, add its documented trait instead of replacing it with a guessed intrinsic.

### Complete nightly example: element-wise transform with a scalar tail

<!-- rust-check: nightly(portable_simd); reason=std::simd requires nightly -->
```rust
#![feature(portable_simd)]
use std::simd::Simd;

fn affine(input: &mut [f32]) {
    let (blocks, tail) = input.as_chunks_mut::<8>();
    let gain = Simd::<f32, 8>::splat(2.0);
    let offset = Simd::<f32, 8>::splat(1.0);

    for block in blocks {
        let values = Simd::from_array(*block);
        *block = (values * gain + offset).to_array();
    }
    for value in tail {
        *value = *value * 2.0 + 1.0;
    }
}

fn main() {
    let mut values = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
    affine(&mut values);
    assert_eq!(values, [1.0, 3.0, 5.0, 7.0, 9.0, 11.0, 13.0, 15.0, 17.0]);
}
```

This uses ordinary slice splitting: no alignment assumptions, no unchecked pointers, no out-of-bounds load, and no dropped tail. Floating-point multiply/add *may* differ in rounding from alternative formulations when contraction or reassociation is allowed; verify any required exactness separately.

### Complete nightly example: integer reduction, including overflow policy

<!-- rust-check: nightly(portable_simd); reason=std::simd requires nightly -->
```rust
#![feature(portable_simd)]
use std::simd::{num::SimdUint, Simd};

fn checksum_mod_256(bytes: &[u8]) -> u8 {
    let (blocks, tail) = bytes.as_chunks::<16>();
    let mut lanes = Simd::<u8, 16>::splat(0);

    for block in blocks {
        lanes += Simd::from_array(*block);
    }
    tail.iter().fold(lanes.reduce_sum(), |sum, &byte| {
        sum.wrapping_add(byte)
    })
}

fn main() {
    let bytes = [255_u8, 2, 4, 10, 250];
    assert_eq!(checksum_mod_256(&bytes), 9);
}
```

Integer SIMD `+`, `-` and `*` wrap **even in debug builds**; `reduce_sum` and `reduce_product` of integer vectors wrap as well. This is not equivalent to scalar `+` that panics on overflow with overflow checking enabled. Choose explicitly among wrapping, saturating, checked, or widened arithmetic; do **not** silently change the contract by vectorizing. Integer division by zero still panics, and other scalar exceptional cases (such as signed division overflow) need review.

### Complete nightly example: compare, select, and safe gather

<!-- rust-check: nightly(portable_simd); reason=std::simd requires nightly -->
```rust
#![feature(portable_simd)]
use std::simd::{cmp::SimdPartialOrd, Select, Simd};

fn main() {
    let input = Simd::<i32, 4>::from_array([-4, 0, 3, 9]);
    let positive = input.simd_gt(Simd::splat(0));
    let clipped = positive.select(input, Simd::splat(0));
    assert_eq!(clipped.to_array(), [0, 0, 3, 9]);
    assert_eq!(positive.to_bitmask(), 0b1100);

    let table = [11, 22, 33];
    let indices = Simd::<usize, 4>::from_array([2, 8, 1, 0]);
    let gathered = Simd::<i32, 4>::gather_or(&table, indices, Simd::splat(-1));
    assert_eq!(gathered.to_array(), [33, -1, 22, 11]);
}
```

A mask **is not short-circuit control flow**: both operands of `mask.select(a, b)` are evaluated before selection. It cannot make an unsafe load, division by zero, or other trapping computation safe just by selecting away a bad result. Use masked memory APIs, safe operands, or a different algorithm.

## Memory Safety, Tails, and Alignment

Prefer safe `as_chunks`/`as_chunks_mut`, `chunks_exact`, array conversions, and safe slice-based SIMD loads/stores. They work when input is unaligned. Important distinctions:

| Operation | Out-of-range behavior | Review obligation |
| --- | --- | --- |
| `from_slice` / `copy_to_slice` | Panic when fewer than `N` elements | Prove full chunk length or use safe partial load |
| `load_or` / `load_or_default` | Fill absent lanes | Choose a neutral fill for the computation |
| `load_select` / `load_select_or_default` | Suppress disabled/missing lanes | Validate mask and default semantics |
| `gather_or` / `gather_or_default` | Missing indices use fallback | Never silently treat corrupt indices as valid data |
| `scatter` / `scatter_select` | Out-of-bounds writes suppressed | Decide whether ignored bad indices are acceptable |
| `*_ptr` / `*_unchecked` | Unsafe preconditions | Prove every **enabled** lane is valid, initialized, aligned where required, and nonaliasing where required |

An OOB index passed to *safe* `scatter` is skipped, not trapped. Duplicate indices have a documented last-lane-wins result for the safe scatter methods; review whether this is the intended contract rather than assuming disjoint writes or commutative updates. Scatter is **not** an atomic scatter-add. Do not use lane writes as synchronization between threads.

`Simd<T, N>` has the element-array's **shape**, but often greater alignment. It is **not** sound to reborrow an arbitrary `&[T]` as `&[Simd<T, N>]` just because the byte count divides evenly, nor to assume that a `Mask` has any particular in-memory representation. The safe `from_array`/`to_array` conversions avoid these problems; the docs describe when transmuting values is sound, but it is rarely required.

If unavoidable, raw pointer loads/stores of SIMD vectors must honor alignment, provenance, initialization, aliasing, and valid ranges. `read_unaligned`/`write_unaligned` address **only the alignment** obligation, not invalid memory. `slice::as_simd` (when available on the chosen toolchain) provides an aligned SIMD middle with prefix and suffix; benchmark whether its alignment handling pays off. Do not cast a `T`-aligned pointer to `*const Simd<T, N>` and dereference it with `read` without proving the stricter alignment.

**Tail policies are algorithmic:** scalar cleanup for short tails is usually simplest; masked loads/stores can avoid branches; zero/neutral fills only work when the operation's identity makes that safe. With min/max, division, comparisons, NaNs, scans, and nonlinear transforms, filling with zero may change the answer. Check length 0, 1, `N-1`, `N`, `N+1`, and nonmultiples of `N`.

## Numeric Semantics That Must Be Preserved

### Integer arithmetic and conversion

- SIMD integer arithmetic wraps, unlike debug scalar arithmetic. A `u8x16` accumulator can wrap long before a `u64` scalar sum; widen **before** summing if the specification requires a wider result.
- Saturating operations are separate (`SimdInt` / `SimdUint`), not implied by using SIMD. Checked arithmetic requires extra logic; a mask selecting a value **after** overflowing is not a substitute.
- Signedness, widening, truncation, shift counts, and conversions must match the scalar contract. `cast` is a **numeric conversion**, not a promise to preserve all bit patterns. For reinterpretation, use documented bit-level APIs (for floats, `to_bits`/`from_bits`) or reviewed target-specific bitcasts.
- For reductions, choose whether modular integer addition is intended and whether the accumulator width is sufficient for the largest supported input. In debug differential tests use explicit scalar `wrapping_*` when wrapping is the intended contract.
- Bounds and indices should use appropriate types (typically `usize` for indexing). Narrowing vector indices or casting signed negatives can silently create huge indices; do not depend on safe gather's OOB fallback to conceal this.

### Floating-point arithmetic

- Floating-point addition and multiplication are not associative. SIMD tree reductions, multiple accumulators, FMA contraction, and scalar left-to-right folds may differ in the low bits. **Do not promise bit-for-bit equality** merely because `SimdFloat::reduce_sum` returns a mathematically equivalent sum. State tolerance or exact-order requirements explicitly.
- Portable `simd_min`/`simd_max` aim for scalar `f32::min`/`max`-style NaN behavior, unlike some hardware min/max instructions. If one operand is NaN, the non-NaN operand is returned. Signed zeros can still require explicit tests; `reduce_min`/`reduce_max` may choose either zero sign when both signs are present.
- Comparisons with NaN are unordered. `simd_eq`/`simd_lt` do not implement total ordering; use a deliberate total-order/key transformation if sorting arbitrary bit patterns is required.
- NaN payloads, signed zero, infinities, subnormals, and rounding modes are correctness tests—not incidental benchmark inputs. The portable SIMD docs explicitly note that certain older `armv7` and `powerpc` implementations flush subnormal `f32` to zero.
- Do not silently substitute `fast-math` or target-specific approximate reciprocal/rsqrt/min instructions for semantically stricter portable operations. When approximate functions are acceptable, document error bounds, domain restrictions, and measured benefit.
- Float-to-int conversions, especially unchecked ones, must satisfy every method's preconditions (finite values, representable range, etc.). Predicating the result after an unchecked conversion cannot repair an invalid input.

### Mask, branch, and lane semantics

- Comparisons produce masks, **not** scalar booleans. `mask.any()` and `mask.all()` are reductions with different meanings; `to_bitmask` maps one boolean to each corresponding bit.
- Mask element width must agree with the vector's comparison/memory operation. Do not treat mask representation as `-1`/0 integer lanes except via documented conversions.
- `select` chooses a result per lane but is not a general control-flow suppressor: its inputs have already been evaluated.
- Cross-lane permutations may cause large shuffle costs; a cheap-looking source expression can spill through memory or expand to a large instruction sequence on a target with weaker shuffle support.
- Packing/repartitioning lanes changes signedness, accumulator width, overflow timing, and numerical association; prove semantic equivalence rather than assuming identical vector width means identical results.

## Gather, Scatter, and Irregular Access

Gather/scatter is useful for lookup tables and sparse layouts, but it can be inferior to scalar loads when indices miss cache or hardware lacks fast gather/scatter support.

- Prefer contiguous loads, batched indices, or SoA layouts where those match the workload. If a table is small, compare register shuffles or scalar indexed loads before assuming gather wins.
- `gather_or` and `gather_select` safely handle out-of-bounds indices by fallback. If bad indices indicate corrupted input, validate/return an error rather than quietly masking them.
- `scatter` skips out-of-range stores. Duplicate addresses are resolved by the method's documented lane ordering, not in unspecified concurrent hardware order; **do not** infer atomicity or use the operation for parallel histogram increments.
- For pointer gather/scatter or `unchecked` versions, reason separately about each enabled lane: validity, provenance, initialization, aliasing, and lifetime. A mask false on a lane excludes its access only for APIs that explicitly guarantee masked accesses.
- Track output overlap and aliasing when using raw pointers. A source/destination overlap harmless to a sequential scalar algorithm can require staging or explicit ordering when vectorized.

## Runtime Dispatch and Target Features on Stable Rust

Fleet strict CI requires portable SIMD or ordinary Rust for operations with a portable implementation. The stable native-intrinsics example below is for external stable-only environments, not strict-CI projects. In fleet projects use the central exact-name exceptions only for genuinely hardware-specific operations (see policy-wasm/README.md).

Portable SIMD source code and CPU feature detection solve **different problems**. An optimized kernel may require AVX2, NEON, or WebAssembly SIMD, while the public entry point must still work on the target's supported baseline.

- Whole-program `-C target-cpu` / `-C target-feature` affect every compiled code path. Use these only when deployment targets satisfy the resulting instruction requirements.
- `#[target_feature(enable = "...")]` marks a function's required features. Calling it from an ordinary function is unsafe even after an `if` feature test; the justified unsafe boundary remains explicit.
- On x86/x86-64, use `is_x86_feature_detected!` and supply a true baseline implementation. On AArch64, investigate baseline target features and `is_aarch64_feature_detected!` for optional features; on WebAssembly, choose the negotiated `simd128` target features/configuration and do not invent x86-style runtime probing.
- The exact required features matter (for example, AVX2 and FMA are distinct). Do not infer AVX-512 availability merely from AVX2, a CPU family label, or a benchmark run.
- Feature-enabled functions and their callees must not accidentally escape into a baseline entry point without the required dispatch. Be careful with function pointers, callbacks, inlining, LTO, library boundaries, and build-wide `RUSTFLAGS`.
- Dispatch once per sizable buffer when possible, rather than probing or using indirect calls on every small vector. If dispatch is cached, make initialization race-safe, process-wide assumptions explicit, and ensure tests exercise every implementation.

### Complete stable example: correctly dispatched AVX2 XOR with a tail

```rust
fn xor_scalar(data: &[u32]) -> u32 {
    data.iter().fold(0_u32, |sum, &value| sum ^ value)
}

#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
fn xor_avx2(data: &[u32]) -> u32 {
    use std::arch::x86_64::{
        _mm256_loadu_si256, _mm256_setzero_si256, _mm256_storeu_si256, _mm256_xor_si256,
    };

    let mut acc = _mm256_setzero_si256();
    let mut chunks = data.chunks_exact(8);
    for chunk in &mut chunks {
        // SAFETY: chunks_exact(8) provides 8 initialized u32 values.
        // The intrinsic is an unaligned load and AVX2 is enabled here.
        let values = unsafe { _mm256_loadu_si256(chunk.as_ptr().cast()) };
        acc = _mm256_xor_si256(acc, values);
    }

    let mut lanes = [0_u32; 8];
    // SAFETY: lanes has 32 writable bytes; this is an unaligned store.
    unsafe { _mm256_storeu_si256(lanes.as_mut_ptr().cast(), acc) };
    let vector_result = lanes.into_iter().fold(0_u32, |sum, value| sum ^ value);
    chunks.remainder().iter().fold(vector_result, |sum, &value| sum ^ value)
}

fn xor_dispatch(data: &[u32]) -> u32 {
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("avx2") {
        // SAFETY: runtime detection established AVX2 before this call.
        return unsafe { xor_avx2(data) };
    }
    xor_scalar(data)
}

fn main() {
    assert_eq!(xor_dispatch(&[1, 2, 3, 4, 5, 6, 7, 8, 9]), 1);
}
```

This example computes a real result and consumes the remainder; it is not a benchmark claim that AVX2 XOR is faster than an auto-vectorized scalar loop. In portable library code, test both the detected path and the forced scalar path. Review `#[target_feature]` ABI/calling requirements in the Rust Reference rather than assuming feature-specific vector arguments are suitable across arbitrary function boundaries.

## API Design and Maintainability

- Keep public APIs in ordinary Rust types (`&[T]`, `&mut [T]`, typed domain results) unless the caller specifically needs a vector type and accepts its stability/feature requirements. Expose kernels through small internal modules.
- State required arithmetic semantics, including whether overflow wraps, floating-point tolerances, NaN handling, and error paths. Backward compatibility is not a reason to preserve undocumented numerical accidents.
- Parameterize lane count where it simplifies the implementation, but do not force const-generic polymorphism when the compiler emits worse code or a hardware-specific implementation is genuinely better.
- Prefer one correct scalar reference plus coherent vector kernels over scattered magic constants and repeated partially vectorized code. Use explicit types and traceable load/compute/store boundaries.
- Keep unsupported architecture code out with `cfg`; do not use a platform-only intrinsic in a supposedly portable fallback.
- Watch for high alignment of vector values, stack spills, register pressure, code size, and expensive vector arguments/returns. The `Simd` docs note that passing/returning vectors can use memory ABI paths; judicious inlining of small kernels may help, but measure it.
- Avoid gratuitous `unsafe` for vector arithmetic or tails. When unsafe is necessary, document *precise* invariants for that operation; moving everything under one large unsafe block makes audits harder.
- Use stable crates when a stable public toolchain is mandatory; do not hide nightly behind `RUSTC_BOOTSTRAP` or surprise a downstream project's MSRV.

## Performance Investigation: What to Measure

A SIMD rewrite deserves a benchmark against the correct scalar baseline, not a source-level argument. Measure relevant throughput **and** total operation latency, not merely instructions-per-element.

1. **Workloads:** real input distributions; sizes below one vector, exact multiples, odd tails, L1/L2/LLC-sized buffers, DRAM streams, and irregular/gather-heavy patterns.
2. **Implementations:** original code, scalar optimized reference, auto-vectorized stable code, portable vector kernel, and ISA-specific kernels where justified.
3. **Target matrix:** the oldest supported CPU, current x86-64 with feature levels actually deployed, AArch64/NEON and other material targets, plus a scalar fallback. Check for AVX-512 frequency/power tradeoffs where hardware exhibits them; do not assume a universal slowdown.
4. **Builds:** release `opt-level`, `target-cpu`, `target-feature`, LTO/codegen units, PGO settings, and compiler version; compare under a controlled toolchain. Preserve the repository's sccache policy for all Cargo/rustc builds.
5. **Measurement:** repeat runs, pin cores where appropriate, control background load/temperature/frequency, use `black_box` or another robust observable output, and avoid folding constants or dead-code elimination.
6. **Counters:** cycles, retired instructions, branch misses, cache misses, vector instruction counts, allocations, and memory bandwidth when available. A reduction in instructions can still lose to shuffle overhead, cache stalls, or expensive gathers.
7. **Generated code:** inspect assembly/LLVM IR with a reproducible release command (`cargo asm`, `objdump`/`llvm-objdump`, or `--emit=asm`). Confirm actual vector widths, scalar remainder, loads, spills, feature-specific instructions, and baseline portability.
8. **Regressions:** compare with the compiler's native vectorization after every substantial toolchain change. One good assembly listing is not a permanent promise across compiler versions.

Avoid `opt-level=0` as evidence of production SIMD performance, and avoid running microbenchmarks concurrently on the same shared machine. A 2× kernel speedup does not imply 2× application speedup when the kernel is only a fraction of runtime or is memory-bound.

## Correctness and Regression Test Matrix

Build a scalar oracle whose semantics **explicitly match** the intended vector contract. For integer modular operations, the oracle uses wrapping arithmetic. For precise floating point, use an agreed tolerance (absolute, relative and, where appropriate, ULP) *or* a numerically stable algorithm with stated error bounds.

- **Lengths:** empty; `1`; `N-1`; `N`; `N+1`; several vectors; random nonmultiples; very long input.
- **Alignment:** aligned and every relevant misalignment/offset; contiguous and strided inputs; overlapping raw-pointer regions only if the API permits them.
- **Values:** zero, extrema, values that wrap, negative signed values, subnormals, positive/negative zero, NaN, infinities, divisors 0, conversion boundaries, and mask patterns all-false/all-true/alternating/single lane.
- **Indexed operations:** index 0, last valid, one-past-end, huge indexes, duplicates, unsorted gather/scatter patterns, and disabled OOB lanes.
- **Behaviors:** exact output length, no dropped remainder, no unexpected mutation outside intended range, correct neutral fill, stable error handling, no uninitialized reads.
- **Architectures:** force scalar and every available SIMD kernel; include systems *without* the optional feature in CI or emulation when feasible. Build checks alone do not prove a target-feature path executes correctly.
- **Methods:** unit tests and property/differential tests for pure kernels, cross-target CI, sanitizer tests of unsafe memory logic where supported, and benchmarks as separate regression evidence.
- **Changes:** nightly compiler/API upgrades (portable SIMD remains unstable), `target-cpu` changes, and new vector widths require revalidation.

For SIMD involving float minima/maxima or masked arithmetic, explicitly test NaN and signed-zero semantics. In-place mutation should be tested against separate input/output buffers if aliasing or access order can affect results.

## Manual Review Checklist

Flag the implementation if any answer is "no" without a documented reason:

1. **Need:** Is there benchmark evidence that explicit SIMD helps the actual application over optimized scalar code?
2. **Toolchain:** Is the API supported by the project's agreed stable/nightly toolchain? Is the optional feature isolated from stable callers?
3. **Contract:** Do overflow, casts, rounding, NaNs, signed zero, saturation, error cases, and observable order match the intended scalar semantics?
4. **Completeness:** Does the kernel process every element, including short and irregular tails?
5. **Memory:** Are loads, stores, alignment, pointer provenance, disabled lanes, gather/scatter OOB and duplicates all correct?
6. **Masking:** Does any code assume that selecting a safe output prevents evaluation of unsafe inputs?
7. **Dispatch:** Can baseline CPUs execute the entry point and all called code? Is runtime detection *and* the unsafe call boundary correct?
8. **Portability:** Are fallback implementations and non-x86 targets maintained and covered?
9. **Performance:** Were production flags, representative data, assembly, frequency/bandwidth constraints, and multiple hardware profiles checked?
10. **Maintainability:** Is unsafe narrowly scoped, semantics explicit, and the scalar reference retained for regressions?

## See Also

- [opt-target-cpu](./opt-target-cpu.md) - CPU feature contracts and dispatch.
- [opt-bounds-check](./opt-bounds-check.md) - Sound indexing and code-generation checks.
- [num-overflow-explicit](./num-overflow-explicit.md) - Overflow semantics.
- [num-float-compare](./num-float-compare.md) - Floating-point equality and ordering.
- [perf-profile-first](./perf-profile-first.md) - Profiling discipline.

## References

- [Rust 1.100 `std::simd` module](https://doc.rust-lang.org/1.100.0/std/simd/index.html) (still unstable) and [nightly `core::simd`](https://doc.rust-lang.org/nightly/core/simd/index.html).
- [`Simd<T, N>`: layout, ABI, memory, gather/scatter](https://doc.rust-lang.org/nightly/core/simd/struct.Simd.html).
- [`Mask` representation and operations](https://doc.rust-lang.org/nightly/core/simd/struct.Mask.html).
- [`SimdInt`](https://doc.rust-lang.org/nightly/core/simd/num/trait.SimdInt.html), [`SimdUint`](https://doc.rust-lang.org/nightly/core/simd/num/trait.SimdUint.html), [`SimdFloat`](https://doc.rust-lang.org/nightly/core/simd/num/trait.SimdFloat.html).
- [Rust Reference: `#[target_feature]`](https://doc.rust-lang.org/reference/attributes/codegen.html#the-target_feature-attribute), [portable SIMD feature tracking](https://github.com/rust-lang/rust/issues/86656).
- Related rules: [`opt-target-cpu`](./opt-target-cpu.md), [`opt-bounds-check`](./opt-bounds-check.md), [`opt-cache-friendly`](./opt-cache-friendly.md), [`num-overflow-explicit`](./num-overflow-explicit.md), [`num-float-compare`](./num-float-compare.md), [`perf-profile-first`](./perf-profile-first.md).
