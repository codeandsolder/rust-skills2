# proj-cargo-artifact-layout

> Consume Cargo's supported artifact discovery interfaces instead of depending on intermediate build paths, especially with shared caches and worktrees

**Rule**: `proj-cargo-artifact-layout`

## Why It Matters

Cargo 1.100 reorganizes intermediate build outputs into per-build-unit directories with configuration hashes. This avoids collisions when feature sets or worktrees share a build directory, but breaks scripts that assume old paths like `target/debug/deps/libname-hash.rlib` or an internal `build-dir` layout.

Use Cargo's JSON messages (especially `compiler-artifact` with `filenames` and `executable`) to locate outputs, or explicitly documented target locations when appropriate. The intermediate layout is **not a public API**.

## Good: Discover Artifacts from Cargo

```bash
# Inspect canonical compiler-artifact messages rather than globbing deps/.
cargo build --locked --message-format=json
```

A consumer should parse complete JSON records, select the desired package/target/profile, and use the returned paths; do not infer hash, platform suffix, or directory nesting. Non-JSON stdout from invoked tools may coexist with JSON and must not be mistaken for a compiler-artifact record.

## Worktree and Cache Rules

- Keep a single normalized `CARGO_TARGET_DIR` per build invocation; relative paths must not change meaning when a script changes working directory.
- Shared-target concurrency still requires normal Cargo locking and correct rustc invocation; don't bypass the configured sccache wrapper to chase hits.
- Remove old path hacks if they worked around the former incomplete build hash; keep tests for distinct features, targets, profiles, and concurrent worktrees.
- Treat `target/` as disposable compiler output, not as durable data to check in or scatter across disks.

## See Also

- [proj-build-rs-minimal](./proj-build-rs-minimal.md) — build-script output contracts
- [test-nextest-workflow](./test-nextest-workflow.md) — target matrix checks
- [Cargo 1.100 changelog](https://doc.rust-lang.org/cargo/CHANGELOG.html#cargo-1100-2026-11-12)
