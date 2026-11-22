# opt-lto-release

> Evaluate ThinLTO and fat LTO for the actual release artifact; choose based on measured optimization benefit and build cost

## Why It Matters

Link-time optimization can expose code from different compilation units and crates to additional optimization, including inlining and dead-code elimination. It can also increase build time, memory use, and code size. The result depends on the call graph, compiler, target, profile and workload.

## Cargo's Four Settings

| Setting | Meaning |
|---|---|
| `false` (default) | Local ThinLTO across codegen units when applicable; no cross-crate LTO |
| `"off"` | Disable LTO, including local ThinLTO |
| `"thin"` | ThinLTO across the dependency graph |
| `"fat"` or `true` | Fat LTO across the dependency graph |

Cargo documents that local ThinLTO is not performed with opt-level 0 or one codegen unit. Cross-language LTO and dynamically linked native components require their own compatible toolchain and linking contracts.

## Compare Without Changing Semantics

```toml
[profile.release-thin]
inherits = "release"
lto = "thin"

[profile.release-fat]
inherits = "release"
lto = "fat"
```

Use `cargo build --locked --profile release-thin` (and the fat profile) with the same source, feature set, target, compiler and workload. Keep panic strategy, overflow checking, CPU features and diagnostic information equivalent. Measure build time, peak memory, binary size and runtime. Use the actual artifact locations from Cargo's JSON output.

Fat LTO is not a guarantee of faster runtime than ThinLTO; ThinLTO is not a guarantee of smaller build cost for every program. Do not infer either from the names.

## Toolchain-Specific Regressions

A reported interaction between fat LTO and x86-64-v3 (rust-lang/rust#146497) is a compiler regression to evaluate on the selected toolchain and workload, not a permanent ban on that target/optimization combination. Verify its status and reproduce significant changes before recommending a workaround.

The package's profile is not the release profile of downstream applications. Cargo reads profiles from the workspace root; package-specific overrides cannot set LTO, panic strategy or rpath.

## See Also

- [opt-codegen-units](./opt-codegen-units.md)
- [opt-target-cpu](./opt-target-cpu.md)
- [perf-release-profile](./perf-release-profile.md)
- [perf-benchmark-regression](./perf-benchmark-regression.md)
- [Cargo profiles: LTO](https://doc.rust-lang.org/cargo/reference/profiles.html#lto)
