# proj-native-build-orchestration

> Prefer native Cargo build, test and artifact-discovery interfaces; express nontrivial orchestration as typed programs instead of Makefile or shell-based application logic.

## Why It Matters

Wrapping an existing build system in another implicit build system duplicates dependency selection, target layout, feature resolution, compiler flags and failure handling. Hidden shell defaults and exported variables can make builds depend on launch context, cause stale or misplaced artifacts, and undermine cache correctness. A benchmark matrix, retrying test supervisor or deployment plan is application logic, not a list of shell commands.

## Bad

```sh
export RUSTFLAGS="-C target-cpu=native"
export CARGO_TARGET_DIR=build
export BENCH_CASES="read,write"
cargo build --release
for case in ${BENCH_CASES//,/ }; do
    build/release/bench "$case" >> results.txt
done
```

The wrapper assumes Cargo's output path, hides compiler policy, and encodes the benchmark protocol in shell.

## Good

Use a real Cargo binary target (for example, a benchmark controller) with explicit scenario arguments or a validated plan. Invoke it with Cargo using the required profile and features; use Cargo's structured artifact messages when a separate build and execution step is necessary.

```sh
cargo run --locked --release --bin benchctl -- run --plan plans/storage.toml
```

The controller owns validation, scheduling, subprocess exit handling, cancellation, and structured results. Compiler configuration belongs at the appropriate Cargo or toolchain boundary; the controller does not invent a separate compiler wrapper or cache.

## Decision guide

- Use Cargo workspaces, targets, features, profiles, test filters and supported configuration directly. Avoid a Make target that does nothing except rename one Cargo command.
- Keep CI YAML responsible for actual CI concerns: triggers, runner selection, permissions, artifact transfer, and calls to shared workflows. Keep policy constants in their authoritative implementation.
- Use a typed CLI for test/benchmark matrices, dependency graphs, retries, process supervision and report generation. Do not substitute a new shell script with the same untyped protocol.
- Preserve necessary small shell adapters to foreign tools and established upstream build systems, including kernel Kbuild, OpenWrt, CMake and vendor firmware builds. Do not rewrite inherited build systems merely because they use Make.
- Respect toolchain contracts, explicit target directories, compiler cache configuration, and foreign build requirements. Do not clear wrappers, start unmanaged caches, or assume a target directory's internal layout.
- Keep resource ownership through subprocess completion. A shell that owns a temporary directory through an EXIT trap must not replace itself with the benchmark process using `exec`, because the trap will not run. Direct `exec` is appropriate for adapters that own no cleanup.
- Avoid preserving superseded entrypoints as compatibility wrappers unless real consumers require them; update callers together.

## See Also

- [proj-explicit-configuration](./proj-explicit-configuration.md) - Explicit configuration
- [proj-cargo-artifact-layout](./proj-cargo-artifact-layout.md) - Discover Cargo artifacts
- [proj-build-rs-minimal](./proj-build-rs-minimal.md) - Deterministic build scripts
- [proj-workspace-deps](./proj-workspace-deps.md) - Central dependency configuration
