# Rust 1.99 → 1.100 migration guide

Rust 1.100.0 was released on **2026-11-12**. This guide is for maintainers
upgrading a codebase's ordinary development, CI, and production compiler from
1.99.x to 1.100.0. The repository's `package.rust-version` (MSRV) is a separate
compatibility contract; do not raise it merely because the local toolchain
changed.

Primary sources: [1.100 announcement](https://blog.rust-lang.org/2026/11/12/Rust-1.100.0/),
[complete Rust 1.100 release notes](https://doc.rust-lang.org/releases.html#version-11000-2026-11-12),
[Cargo 1.100 changelog](https://doc.rust-lang.org/cargo/CHANGELOG.html#cargo-1100-2026-11-12).

## Recommended migration sequence

1. Preserve the existing dependency graph and lockfile; record 1.99.x test results.
2. Install `1.100.0` and run all-target check, tests, doc build, and the project's
   ordinary Clippy policy with the **new compiler**, not just a newer Cargo binary.
3. Investigate new inference, diagnostics, feature and ABI behavior **before**
   combining with dependency bumps.
4. Test every relevant target/platform/feature variant; when the lint is applicable,
   build the full set of targets for Cargo's unused-dependency analysis.
5. Update pinned development/CI toolchains and artifact discovery scripts; preserve
   sccache and its ordinary, configuration-sensitive cache keys.
6. Only after successful compiler migration consider changes to cargo registry
   cooldown policy, dependency versions, or public MSRV.

```bash
rustup toolchain install 1.100.0 --profile minimal --component clippy,rustfmt
cargo +1.100.0 check --locked --workspace --all-targets
cargo +1.100.0 test --locked --workspace
cargo +1.100.0 doc --locked --workspace --no-deps
CARGO_BUILD_WARNINGS=deny cargo +1.100.0 clippy --locked --workspace --all-targets -- -D warnings
# Also exercise the actual supported --all-features / --no-default-features matrix.
```

A locally installed non-rustup Cargo executable can intercept `cargo +1.100.0`:
confirm both `rustc -V` and `cargo -V` in the build environment, or execute
the versioned toolchain executables by absolute path. Keep `RUSTC_WRAPPER`
configured to sccache; do not bypass it for migration testing.

## Language: never type is fully stable, with a compatibility change

`!` now works in generic positions: `Result<T, !>`, `ControlFlow<!, T>`,
and other type parameters. `std::convert::Infallible` becomes a **type alias**
of `!` rather than a separate enum. Old `Infallible` usage remains useful
for crates supporting pre-1.100 compilers, but beware treating the two as
distinct in trait-coherence logic.

The never-type fallback is now `!` in **every edition**, including 2015,
2018 and 2021. It was already `!` in Edition 2024; the old fallback for
pre-2024 editions was `()`. Generic result inference, trait bounds, and
unreachable-code diagnostics can change. Fix genuinely ambiguous code with
type annotations rather than suppressing
`dependency_on_unit_never_type_fallback` or
`never_type_fallback_flowing_into_unsafe`.

```rust
fn infallible() -> Result<u32, !> {
    Ok(7)
}
fn main() {
    let Ok(n) = infallible(); // exhaustive on 1.100
    assert_eq!(n, 7);
}
```

Other compatibility-sensitive compiler changes: `if let` closure captures are
more precise, dyn-compatibility is checked in more positions, `box` patterns
are rejected syntactically, `let-else` with `macro_rules!` expr metavariables
respects grouping, and generic `Box` allocator impls may create inference
ambiguity. The new trait solver is enabled by default during orphan checks;
review changed overlap/coherence diagnostics rather than hiding them.

Rust 1.100 stabilizes `extern "custom"` support for user-defined ABI integration.
This is *not* a promise that arbitrary external calling conventions work:
verify the target's ABI, toolchain and linker contract.

## Library: allocator-aware ownership

`std::alloc::Allocator`, `Global` and `System`, and allocator-aware variants
of `Vec<T, A>` and `Box<T, A>` become stable. Important APIs include:

- `Vec::new_in`, `Vec::with_capacity_in`, `Vec::allocator`,
  `Vec::into_raw_parts_with_allocator` / `Vec::from_raw_parts_in`,
  and `Vec::into_parts_with_allocator` / `Vec::from_parts_in`;
- `Box::new_in`, `Box::allocator`,
  `Box::into_raw_with_allocator` / `Box::from_raw_in`,
  and `Box::into_non_null_with_allocator` / `Box::from_non_null_in`;
- relevant allocator-parameterized impls for references to allocators, boxes,
  `Rc` and `Arc`.

**Migration risk:** do not drop or substitute the returned allocator when
reconstructing owned storage from raw parts. Length, capacity, alignment,
element layout, and ownership must match. An `Allocator` implementation is
unsafe and must honor all allocation/deallocation requirements.

Do not assume this enables all `allocator_api` APIs or every standard
collection; the release stabilizes a specific subset. Existing global-allocator
collections need no change unless the memory policy genuinely benefits.

## Library: cleanup, ZST construction, interior mutability

- `core::mem::DropGuard::new(value, f)` runs `f` on drop;
  `DropGuard::dismiss` extracts the value without executing `f`. Useful for
  rollback on early `?`/return/unwinding; do not assume it runs on abort or
  process exit. See [mem-drop-guard](../rules/mem-drop-guard.md).
- `std::mem::conjure_zst::<T>()` is an **unsafe** constructor for an
  inhabited zero-sized value. A zero-sized GIL/lock/authority token can carry
  nontrivial validity invariants: `size_of::<T>() == 0` alone is not a
  safety proof. See [unsafe-conjure-zst](../rules/unsafe-conjure-zst.md).
- `UnsafeCell::replace`, `as_ref_unchecked` and `as_mut_unchecked` are stable.
  They do not remove reference aliasing restrictions or make a data race safe.
  Prefer `get_mut` or checked wrappers when possible.
- `Box::take` yields the extracted value plus an uninitialized box for reuse;
  `Box::map`, `Rc::map` and `Arc::map` add owned-value mapping. Inspect each
  ownership/reuse contract individually.

## Library: smaller ergonomic APIs

- `Vec::from_fn(length, |index| value)` initializes a fixed number of elements
  in ascending index order.
- `str::trim_prefix` / `trim_suffix` and `[T]` equivalents remove **optional**
  affixes while keeping the original borrowed value when unmatched;
  `Path::trim_prefix` covers paths. Use `strip_prefix` where lack of a prefix
  is an error.
- `bool::toggle` changes a mutable boolean in place.
- `Once::default` and `Child::main_thread_handle` are newly available.
- `Cow`/`Vec` and `Cow`/slice comparisons gain impls; code relying on old
  inference/trait selection should be tested.
- On Windows, `CommandExt::show_window` is stabilized for process creation.
- Error mapping now categorizes `ENOTSUP` as `ErrorKind::Unsupported`.
  Review matching logic if error categories are persisted or compared.

## Cargo: native manifest lints and dependency cooldown

Cargo 1.100 stabilizes `[lints.cargo]` and the new
`cargo::unused_dependencies` lint (warn by default). It can only establish
unused ordinary dependencies when **every relevant target** has been built;
`dev-dependencies` do not currently receive this warning. Distinguish it
from rustc's `unused_crate_dependencies` and the unrecognized
`unused_features` Cargo lint.

```toml
# A package manifest that elects to deny unused ordinary dependencies:
[lints.cargo]
unused_dependencies = "deny"
```

`registry.global-min-publish-age` is stable and skips dependency versions
younger than the configured cooldown during resolution.

```toml
# .cargo/config.toml
[registry]
global-min-publish-age = "3 days"
```

Already-locked versions are not filtered; timestamps are taken from the
registry's `pubtime` metadata, and versions lacking it are not delayed.
`cargo install` ignores minimum publish age. Its behavior also changes:
a packaged `Cargo.lock` is now used by default, making `--locked` a no-op
for that specific enforcement. Do not mistake this for fully reproducible
dependency resolution when publishing a crate without the intended lockfile.

Fleet policy may have its **own** age quarantine checks. Align the two
deliberately rather than accidentally stacking incompatible windows.

## Cargo: build directory and cache migration

Intermediate artifacts now use a build-unit-oriented layout with
configuration hashes in directories rather than the former file-level
arrangement. The old internal `target/.../deps/...` layout is not a stable
interface. Scripts that glob guessed `.rlib`/`.rmeta`/build-script paths
should consume `cargo --message-format=json` `compiler-artifact` messages
and their recorded `filenames` instead. Test differing features, profiles,
targets, and concurrent worktrees that share a build directory.

Keep `CARGO_TARGET_DIR` consistent across script `cd` boundaries and leave
`RUSTC_WRAPPER=sccache` intact. Do not attempt to win cache hits by sharing
artifacts across incompatible Rust flags or versions.

## Diagnostics, rustdoc and target compatibility

- New/revised diagnostics cover duplicate `#[repr(...)]` attributes,
  `dropping_references` / `dropping_copy_types` /
  `undropped_manually_drops` for `drop_in_place`, and the
  deny-by-default `aligned_fields_in_packed` lint. Fix the violations;
  do not globally downgrade them.
- Rustdoc introduces `invalid_markdown_table`; run doc builds in CI.
- Stable `-Cprofile-sample-use` allows **sample-based PGO** with a compatible
  LLVM profile, not raw `perf.data`. Benchmark it and let compilation-profile
  flags create separate cache keys.
- `wasm32-wasip3` is now Tier 2; `i686-pc-windows-gnu` no longer has
  host tools (Tier 2 target only); `powerpc64-sony-ps3` is new Tier 3.
- ARM `-Ctarget-feature` / `-Ctarget-cpu` options that change the ABI
  are now rejected. The corrected ARMv7-A hardfloat baseline may require
  an explicit `+d32` for projects relying on that older configuration.
  x86 softfloat targets reject SSE/AVX enabling.
- Xtensa ABI selection, Windows GNU/LLVM linking, and aarch64 Fuchsia
  CPU erratum defaults may change target-specific builds.
- The standard library updates to **Unicode 18.0.0**; test Unicode-dependent
  matching and output snapshots, and note `str::escape_debug` now always
  escapes grapheme extenders.
- `Iterator::min` / `max` (and `_by_key` versions) can choose different
  `Ord` methods; only inconsistent `Ord` implementations should observe
  behavioral differences.

## Signoff checklist

- [ ] Rustc **and Cargo** report 1.100.0 in the verification environment.
- [ ] Check/test/doc/Clippy and project-specific fixtures pass with existing
      locked dependencies and mandatory sccache.
- [ ] All supported feature, target, build-script and proc-macro variants run.
- [ ] Never-type/inference changes and allocator/raw-ownership contracts reviewed.
- [ ] Cargo unused-dependency results reviewed using the correct target coverage.
- [ ] Scripts no longer guess intermediate Cargo artifact paths.
- [ ] Cargo publish-age configuration is consistent with existing quarantine.
- [ ] Platform/ABI/Unicode changes validated where relevant.
- [ ] `package.rust-version` is preserved unless the public compatibility
      contract is intentionally being raised.
