# Changelog

All notable changes to this skill are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
semantic versioning for the rule set.

## [Unreleased]

### Added
- Strict nightly Clippy denies `deprecated_attributes_without_note` and
  `must_use_without_reason` in all targets, including relaxed tests. Both
  are non-suppressible in handwritten source; regression fixtures verify
  each specific diagnostic and suppression rejection.
- Added actionable deprecation guidance and an independent CI package that
  compiles and executes nightly examples instead of excluding them from validation.
- Added a packaged, compiler-versioned nightly feature guide and a comparison of
  Rust/Clippy 1.100.0 versus 1.102.0-nightly, including new restriction-lint
  candidates and recorded upcoming stabilizations.

### Changed
- Corrected stale stability claims about free iterator chaining, const generic
  defaults, and the never type; refreshed try-block, SIMD, and branch-hint guidance.
- Expanded `opt-simd-portable` into a comprehensive SIMD implementation and
  review guide: nightly portable SIMD APIs, integer/floating-point semantics,
  mask and memory safety, lane tails, gather/scatter, runtime CPU dispatch,
  reliable benchmarks, target compatibility, and differential tests. Replaced
  the incomplete AVX2 sample with a functional dispatched XOR kernel.

## [2.2.0]

### Added
- **Modernized for Rust 1.100.0 (2024 edition)**, with 12 focused new rules
  covering stable allocator-parametric ownership, `DropGuard`, zero-sized
  construction soundness, `UnsafeCell` accessors, box mapping/reuse, prefix
  trimming, `Vec::from_fn`, Cargo-native unused-dependency linting, native
  dependency cooldowns, artifact discovery, sample-based PGO, and rustdoc tables.
- Added a release-specific [Rust 1.99 → 1.100 migration guide]
  (docs/migration-rust-1.99-to-1.100.md) covering compiler compatibility,
  stdlib APIs, Cargo resolution/layout, cache behavior, lint changes,
  platforms and ABI changes, and an actionable verification checklist.

### Changed
- Fixed never-type rule: `Result<T, !>` is stable, `Infallible` is now an
  alias for `!`, and the never-type fallback change affects all editions.
- Clarified that Cargo's lint **infrastructure** is stable while its
  unused-feature lint remains experimental.
- Moved the example compiler/checker and GitHub Actions CI to Rust 1.100.0;
  kept project MSRV distinct from the development compiler.
- Preserved the shared sccache policy and dependency quarantine rather than
  introducing parallel cache or resolver mechanisms.

## [2.1.0]

### Added
- Workspace-aware strict CI policy propagation: every selected Cargo workspace
  member is covered automatically, with scoped package/workspace metadata
  overrides for test/bench panic ergonomics. Production and examples remain
  strict, mixed workspaces split strict and relaxed test passes, and every
  metadata relaxation requires an explicit reason.

### Changed
- The shared strict gate now resolves effective per-package test policy through
  `cargo metadata`, with precedence package metadata → workspace metadata →
  reusable-workflow input. This removes the need for per-crate lint wiring while
  keeping exceptions explicit and local.

## [2.0.0]

### Added
- Added the reusable strict nightly-Clippy CI gate and source-policy preflight.
  The gate keeps lint levels at `deny` for proc-macro compatibility while
  rejecting handwritten lint-level downgrades and non-negotiable expectations.

### Changed
- **Modernized through Rust 1.99.0 (2024 edition).** Updated throughout for the
  Rust 2024 edition and current patched stable toolchain. Coverage includes RPIT
  lifetime capture rules, `unsafe extern` blocks, `#[unsafe(no_mangle)]`, let
  chains and Rust 1.95 `if let` match guards, `cfg_select!` (1.95),
  `core::hint::cold_path` (1.95), `core::hint::select_unpredictable` (1.88),
  `Atomic*::update` (1.95), `core::range::Range` (1.96), `assert_matches!`
  (1.96), `From<T> for AssertUnwindSafe<T>` (1.96), `<[T]>::array_windows`
  (1.94), `<[T]>::as_chunks` (1.88), trait object upcasting (1.86),
  `#[diagnostic::do_not_recommend]` (1.85), `cargo publish --workspace` (1.90),
  Tokio 1.52+ APIs, and async-std's discontinuation (March 2025).
- Added Rust 1.99 guidance for stable C-variadic definitions and `VaList`,
  raw-pointer layout queries (`size_of_val_raw`, `align_of_val_raw`,
  `Layout::for_value_raw`), direct raw-borrow review via
  `raw_borrows_via_references`, and ownership handoff via
  `Box::into_non_null` / `Box::from_non_null` instead of leak→unleak.
- Corrected workspace dependency guidance for Cargo 1.99: Edition 2024 members
  can now make inherited `default-features = false` effective, which can
  change the resolved feature set on a toolchain-only upgrade.
- Added a structured Rust 1.88 → 1.99 migration guide covering compiler/Cargo
  behavior changes, target-specific checks, high-value APIs, and a staged
  upgrade procedure that keeps compiler and dependency changes separate.
- Added Rust 1.98 guidance for `core::fmt::NumBuffer` + primitive integer
  `format_into` in measured hot paths, `f32`/`f64::algebraic_*` as an explicit
  relaxed/reassociated arithmetic contract, and `str::substr_range` /
  `[T]::subslice_range` for recovering source spans from borrowed views.
- Added Rust 1.97 CI/lint guidance: prefer Cargo-native
  `CARGO_BUILD_WARNINGS=deny` over injecting warning denial through `RUSTFLAGS`,
  and treat `linker_messages` as its own platform-sensitive lint.
- Expanded MSRV guidance to separate the compatibility floor from the normal
  patched current-stable development/build toolchain, call out resolver 3 for
  virtual Rust-2024 workspaces, and distinguish crate MSRV from the development
  manifest/parser MSRV introduced by Cargo 1.94 TOML 1.1 syntax.
- Depth pass: expanded `own-rc-single-thread` (breaking cycles with `Weak`, the
  `Rc::clone` idiom, `strong_count`/`weak_count`, `!Send`/`!Sync`) and
  `own-refcell-interior` (`Cell` for `Copy` types).
- Added cross-references from ~18 foundational rules to the newer categories
  (`conc-`, `conv-`, `num-`, `serde-`, `trait-`, `closure-`, `coll-`, `pat-`)
  for better navigation between related rules.
- Hardened CI and integration-test guidance around mutating formatter/generator
  false-greens, canonical production contracts, stale-capability invalidation,
  application-level readiness versus transport/channel availability, and
  session-ID rotation at authentication or privilege boundaries.

Now 325 rules across 26 categories.

## [1.5.1] (skipped in changelog; documented here retroactively)

### Changed
- Depth pass: expanded `own-rc-single-thread` and `own-refcell-interior`.

## [1.5.0]

### Added
- **Const & Compile-Time** category (`const-`, 4 rules): `const fn`, `const` vs
  `static`, const generics, inline `const { }` blocks.
- **Trait & Generics Design** category (`trait-`, 6 rules): static vs dynamic
  dispatch, associated types vs generic params, default methods, blanket impls,
  object safety, the orphan rule + newtype.
- **Collections** category (`coll-`, 4 rules): map choice (HashMap/BTreeMap/
  IndexMap), sequence choice (Vec/VecDeque), set membership, `BinaryHeap`.
- `checks/gen_index.py` — generates `SKILL.md`'s priority table and Quick
  Reference (and the rule counts) from `rules/` so the index can't drift; CI
  runs it in `--check` mode.
- `CONTRIBUTING.md` and this `CHANGELOG.md`.

Now 265 rules across 26 categories.

## [1.4.0]

### Added
- **Closures** category (`closure-`, 5 rules): Fn/FnMut/FnOnce bounds, returning
  `impl Fn`, `move` capture, static vs dynamic dispatch, disjoint capture.

Now 251 rules across 23 categories.

## [1.3.0]

### Added
- **Serde** category (`serde-`, 8 rules): rename_all, default, skip, flatten,
  enum representation, deny_unknown_fields, custom (de)serialize, validate-on-
  deserialize.
- **Numeric & Arithmetic Safety** category (`num-`, 5 rules): explicit overflow
  handling, `as` vs `TryFrom`, float comparison, clamping, `NonZero`.

Now 246 rules across 22 categories.

## [1.2.0]

### Added
- **Macros** category (`macro-`, 8 rules): declarative-macro hygiene and
  fragment specifiers, and procedural-macro design with `syn`/`quote`.
- **Observability** category (`obs-`, 7 rules): `tracing`, spans, structured
  fields, error chains, and keeping secrets out of logs.

Now 233 rules across 20 categories.

## [1.1.x]

### Added
- **Unsafe Code** (`unsafe-`), **Concurrency** (`conc-`), **Conversions**
  (`conv-`), and **Pattern Matching** (`pat-`) categories, plus new rules across
  existing categories — 39 rules in total.
- A compile-check harness (`checks/`) and a GitHub Actions CI workflow that
  validates rule structure, links, the index, and that examples compile.

### Changed
- Updated throughout for the Rust 2024 edition and current stable (Rust 1.96):
  RPIT lifetime capture rules, `impl Trait` in traits, `collect_into` status,
  `resolver = "3"`, `env::set_var` now `unsafe`, and more.

Now 218 rules across 18 categories.

## [1.0.0]

### Added
- Initial release: 179 rules across 14 categories.

[1.5.0]: https://github.com/leonardomso/rust-skills
[1.4.0]: https://github.com/leonardomso/rust-skills
[1.3.0]: https://github.com/leonardomso/rust-skills
[1.2.0]: https://github.com/leonardomso/rust-skills
[1.1.x]: https://github.com/leonardomso/rust-skills
[1.0.0]: https://github.com/leonardomso/rust-skills