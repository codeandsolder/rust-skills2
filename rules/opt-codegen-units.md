# opt-codegen-units

> Choose release codegen-unit count by measuring runtime, binary size, compilation cost and memory together

## Why It Matters

Cargo divides crate code generation into units to permit parallel LLVM work and incremental reuse. Fewer units can expose more optimization opportunities inside a unit but also reduce parallelism. Local ThinLTO can optimize across units; cross-crate LTO changes the tradeoff further. Neither a single unit nor the default count is guaranteed to produce the fastest or smallest executable.

## Compare Real Profiles

```toml
[profile.release-single]
inherits = "release"
codegen-units = 1

[profile.release-thin]
inherits = "release"
lto = "thin"
```

Use the same workload and correctness criteria for each profile. A custom profile inherits the release settings chosen by that project, so hold the other settings constant when isolating one variable.

```bash
cargo build --locked --profile release-single
cargo build --locked --profile release-thin
```

Identify the actual executables using Cargo JSON artifact messages rather than guessing their paths. Record build wall time, cache behavior, peak memory, runtime, and code size. Use release-equivalent benchmark profiles when running benchmarks, and do not compare an instrumented build against an uninstrumented baseline as though only the unit count changed.

## Guidance

- Cargo normally defaults to 16 units for non-incremental compilation and 256 for incremental compilation. Explicit profile settings can override this.
- A few expensive crates can dominate build memory; measure targeted package settings before changing the entire workspace.
- LTO, incremental compilation and sccache are separate mechanisms. Preserve the configured compilation cache when comparing settings and distinguish warm from cold runs.
- Do not prescribe a percentage speedup, a universal compilation time, or mandatory single-unit release builds.
- A slow compiler/version/target combination is a reason to measure and investigate that combination, not to turn the workaround into a permanent rule.

## See Also

- [opt-lto-release](./opt-lto-release.md)
- [perf-release-profile](./perf-release-profile.md)
- [perf-benchmark-regression](./perf-benchmark-regression.md)
- [Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html)
