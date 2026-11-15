# opt-sample-profile

> Use stable Rust 1.100 `-Cprofile-sample-use` for measured sample-based PGO when the profiler and target match the build

**Rule**: `opt-sample-profile`

## Why It Matters

Rust 1.100 stabilizes `rustc -Cprofile-sample-use=PATH` for sample-based profile-guided optimization. Unlike instrumentation-based PGO, sampling can profile an application under its real workload with lower collection overhead, but the sample profile must be in a format supported by LLVM and accurately correspond to the compiled code.

Use this only for benchmarked release builds, not to claim automatic speedups from merely setting the flag.

## Workflow

```bash
# Once a compatible LLVM sample profile has been produced:
RUSTFLAGS="-Cprofile-sample-use=/path/to/workload.prof" cargo build --release
```

Sample collection is profiler/target-specific, and the `.prof` placeholder is **not** an arbitrary `perf.data` file. Convert samples to the required LLVM sample-profile format, preserve relevant symbol/debug information, and compare representative benchmark distributions before shipping.

Changing `RUSTFLAGS` affects compiler configuration hashes and cache keys. Do not defeat sccache to force reuse across incompatible profiles, or share artifacts from instrumented and non-instrumented builds by guessing target paths.

## See Also

- [mem-hotpath-profile](./mem-hotpath-profile.md) — measure real workloads first
- [proj-cargo-artifact-layout](./proj-cargo-artifact-layout.md) — Cargo's build directory contracts
