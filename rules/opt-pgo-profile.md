# opt-pgo-profile

> Use representative profile-guided optimization when measured end-to-end gains justify its training and build costs

## Why It Matters

Instrumentation-based PGO records execution counts and other information that LLVM can use to make better optimization decisions. The profile must reflect the deployed workload. Training on unrepresentative inputs can regress other paths or overfit a benchmark.

## Instrumentation Workflow

1. Build an instrumented release artifact with `-Cprofile-generate=ABSOLUTE_DIRECTORY`.
2. Run representative workloads using that exact artifact and collect the generated raw profile files.
3. Merge the raw files with the LLVM tool matching the compiler.
4. Rebuild the same source, target, feature set and release configuration with `-Cprofile-use=ABSOLUTE_PROFILE_FILE` instead of the generation flag.
5. Check correctness and compare the final artifact with a non-instrumented baseline on separately selected workloads.

Use `rustup component add llvm-tools-preview` for the selected compiler and find the matching `llvm-profdata` from its toolchain installation (e.g. via the compiler sysroot and host triple). Do not assume the distro's newest LLVM can read every rustc profile format.

## Explicit Cargo Configuration

For a known target, create two configuration files in the project's dedicated build/profiling directory. These are illustrative absolute paths and target names; use the actual project locations:

```toml
# generate.toml
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "profile-generate=/absolute/build/pgo/raw"]
```

```toml
# use.toml
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "profile-use=/absolute/build/pgo/merged.profdata"]
```

Integrate these flags with the project's effective Cargo configuration rather than accidentally replacing its target flags or adding duplicate flags. Pass the configuration explicitly and provide an explicit target so host build scripts and procedural macros do not receive target profiling flags:

```bash
cargo --config /absolute/build/pgo/generate.toml build --locked --release --target x86_64-unknown-linux-gnu
# Run the resulting instrumented binary on representative inputs.
# Merge the fresh *.profraw files with the matching tool.
llvm-profdata merge /absolute/build/pgo/raw -o /absolute/build/pgo/merged.profdata
cargo --config /absolute/build/pgo/use.toml build --locked --release --target x86_64-unknown-linux-gnu
```

Use Cargo JSON artifact records to find each executable; do not assume both
builds have the same layout or keep them in the same directory if they need
to be compared. A tool like cargo-pgo can orchestrate this workflow if its
version and cache behavior fit the project.

Keep raw and merged profiles within a bounded project-owned artifact
directory. Use a fresh generation epoch rather than merging unrelated
stale data; do not clean the shared build cache or bypass sccache.

## Validate Generalization

- Train with representative branch probabilities, data distributions, event rates and concurrency, including relevant error paths.
- Ensure the final profile corresponds to the source and compiler revision. Investigate mismatch/missing-profile diagnostics rather than assuming they are harmless.
- Benchmark a separate validation workload, not just training inputs.
- Compare release semantics, end-to-end speed, tail latency, binary size and compilation cost. There is no universal expected percentage gain.
- Recollect profiles when meaningful changes alter the workload or invalidate profile compatibility.

## Alternatives

Sample-based profiling is a separate mode supported by modern rustc
(`-Cprofile-sample-use`; stable since Rust 1.100). It requires a compatible
LLVM sample profile, not arbitrary raw perf data. See
[opt-sample-profile](./opt-sample-profile.md).

Post-link optimizers such as LLVM BOLT also have specific executable-format,
symbol, relocation and profile-conversion requirements. Consult the chosen
tool's instructions; they are not generic commands applicable to every
Rust binary.

## See Also

- [opt-sample-profile](./opt-sample-profile.md)
- [opt-lto-release](./opt-lto-release.md)
- [perf-benchmark-regression](./perf-benchmark-regression.md)
- [proj-cargo-artifact-layout](./proj-cargo-artifact-layout.md)
- [rustc book: profile-guided optimization](https://doc.rust-lang.org/rustc/profile-guided-optimization.html)
