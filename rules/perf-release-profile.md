# perf-release-profile

> Tune release profiles against real deployment goals; keep semantic settings explicit and preserve the diagnostic information needed by the project

## Why It Matters

Cargo release defaults are a good starting point, not an optimal answer for every workload. Optimization level, LTO and codegen-unit count affect code generation and compilation. Panic strategy and overflow checking can change observable behavior; stripping affects diagnostic tooling. Do not change all of them merely to claim a speed improvement.

## Start From Defaults

```toml
[profile.release]
opt-level = 3
```

Compare a profiling build that retains symbols and an optimization candidate independently:

```toml
[profile.profiling]
inherits = "release"
debug = "line-tables-only"
strip = "none"

[profile.release-thin]
inherits = "release"
lto = "thin"
```

Use `cargo build --locked --profile profiling` to build the former. If a profiler requires more information, use full debuginfo. Measure on representative workloads with the same configuration and inputs; use Cargo's reported artifact path.

## Profile Settings

| Setting | What to decide |
|---|---|
| `opt-level` | 0–3, s or z; benchmark actual speed/size, including 2 versus 3 |
| `lto` | Off, local, thin or fat; measure across crate boundaries |
| `codegen-units` | Parallelism and optimization tradeoff |
| `panic` | Unwinding or abort; not an interchangeable speed knob |
| `overflow-checks` | Checked or wrapping ordinary integer overflow, as defined by Rust |
| `strip` | None, symbols or debuginfo; preserve needed diagnostics |
| `debug` | Debug information level/type required by tools |
| `incremental` | Rebuild characteristics and compilation storage |

The Cargo default for release is opt-level 3, 16 codegen units, LTO false, no incremental compilation, panic unwind on supporting targets and overflow checks disabled. Targets and workspace/config overrides may alter applicable behavior.

## Panic and Diagnostic Data

An aborting panic does not unwind or run normal stack destructors. It cannot be recovered using catch_unwind. Tests/benchmarks and certain compiler targets may not use the configured application panic strategy. Unwind-table emission is target- and compiler-dependent, separate from whether panics unwind; do not claim abort always removes all unwind tables or always preserves usable backtraces.

`strip = "debuginfo"` strips debug information; `strip = "symbols"` strips symbols and can also remove debugging information, depending on the platform/toolchain. Use `strip = "none"` for profiling when symbol and line attribution are required, or deliberately preserve external debug files and verify retrieval. Do not expect stripped ELF or PE binaries to retain every symbol/status needed by diagnostic tools.

## Custom and Workspace Profiles

Cargo reads profile settings from the workspace root. Package overrides can tune eligible settings such as opt-level and codegen-units; they cannot change panic, LTO or rpath per package. Optimizing dependencies in dev builds may speed up tests but increase first-build cost; measure incremental iteration.

Size profiles (`"s"`, `"z"`) are candidates, not guaranteed smallest outputs. Do not strip diagnostics or remove failure checking merely because the deployment target is embedded.

## See Also

- [opt-lto-release](./opt-lto-release.md)
- [opt-codegen-units](./opt-codegen-units.md)
- [opt-pgo-profile](./opt-pgo-profile.md)
- [perf-benchmark-regression](./perf-benchmark-regression.md)
- [Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html)
