# Rust 1.88 → 1.99 migration guide

This guide is for an existing Rust 1.88 codebase moving its normal development
and CI toolchain to Rust 1.99. It focuses on changes that can alter compilation,
linking, dependency features, target behavior, lint results, or unsafe-code
assumptions. It is not a dump of every newly stabilized standard-library API.

The compiler upgrade and the project's MSRV are separate decisions. Moving CI
and normal builds to 1.99 does **not** require changing `package.rust-version`
unless the source, manifest syntax, or public compatibility policy now requires
a newer compiler.

## Recommended migration sequence

Keep the compiler change isolated from dependency churn first:

```bash
rustup toolchain install 1.99.0 --profile minimal --component clippy,rustfmt

cargo +1.99.0 check --locked --workspace --all-targets
CARGO_BUILD_WARNINGS=deny cargo +1.99.0 clippy --locked --workspace --all-targets -- -D warnings
cargo +1.99.0 test --locked --workspace
cargo +1.99.0 doc --locked --workspace --no-deps
```

For applications and workspaces with committed lockfiles, keep `--locked`
during this first pass. That makes failures attributable to the compiler/Cargo
upgrade rather than a simultaneous dependency update.

Then test the feature and target combinations that can change behavior across
this range:

- Edition 2024 workspace members that inherit dependencies and specify
  `default-features = false`;
- `x86_64-unknown-linux-gnu`, because Rust 1.90 changed the default linker to
  LLD;
- `*-linux-musl`, because Rust 1.93 updated bundled musl;
- WebAssembly targets, especially projects relying on unresolved imports;
- Intel macOS if it is still supported, because
  `x86_64-apple-darwin` moved to Tier 2;
- FFI, raw-pointer, allocator, `Pin`, and custom-symbol code;
- doctests and macro-heavy crates under warnings-as-errors.

Only after the compiler-only pass is green should you update the dependency
graph. This keeps regressions bisectable.

## At-a-glance compatibility map

| Release | Migration-sensitive change | What to do |
| --- | --- | --- |
| 1.88 | Let chains in Edition 2024; raw-pointer correctness lints begin tightening | Treat 1.88 as the baseline; fix `dangerous_implicit_autorefs` rather than suppressing it |
| 1.89 | `dangerous_implicit_autorefs` becomes deny-by-default; const-generic `_`; wasm C ABI correction | Audit raw-pointer implicit borrows and any wasm C ABI boundary |
| 1.90 | LLD becomes default on `x86_64-unknown-linux-gnu`; `cargo publish --workspace`; Intel macOS demoted to Tier 2 | Exercise native/linker integration tests and any custom linker flags |
| 1.91 | Warn on raw pointers escaping locals; ARM64 Windows becomes Tier 1 | Fix `dangling_pointers_from_locals`; consider ARM64 Windows a first-class CI target if relevant |
| 1.92 | Never-type future-compat lints become deny-by-default; Linux `panic=abort` emits unwind tables | Fix never-type inference dependencies; re-check binary-size/unwind assumptions |
| 1.93 | Bundled musl 1.2.5; more `MaybeUninit`/raw-parts APIs | Update old `libc` dependencies for musl; simplify hand-written raw-parts code where appropriate |
| 1.94 | Cargo parses TOML 1.1; `array_windows`; new lazy-cell accessors | Distinguish source/development manifest MSRV from published crate MSRV |
| 1.95 | `cfg_select!`; `if let` match guards; stable custom JSON target specs removed | Check custom targets and simplify compile-time cfg dispatch |
| 1.96 | New copyable `core::range` types; `assert_matches!`; stricter wasm undefined symbols | Use `RangeBounds` in public APIs where possible; make wasm imports explicit |
| 1.97 | Symbol mangling v0 default; Cargo-native warning denial; linker messages exposed | Stop using `RUSTFLAGS=-Dwarnings` just for CI policy; inspect platform linker warnings |
| 1.98 | Runtime-symbol lints; stricter `repr(transparent)`; several ambiguity/layout checks tighten | Re-run FFI/layout tests and fix newly rejected ambiguous or invalid representations |
| 1.99 | C-variadic definitions; raw layout APIs; Cargo inherited-feature behavior change; CI incremental off by default | Audit inherited `default-features`, unsafe raw-layout code, leak→unleak patterns, and CI cache assumptions |

## Rust 1.88 — baseline

Rust 1.88 stabilized Edition-2024 let chains, stable naked functions, and boolean
literals in `cfg` predicates. It also introduced the warn-by-default
`dangerous_implicit_autorefs` lint and the `invalid_null_arguments` compiler
lint.

For a project already building on 1.88, the important point is that the raw
pointer diagnostics introduced here continue tightening in later releases.
Do not preserve code that only happens to compile because an implicit reference
is created and immediately converted back to a raw pointer.

Useful APIs that entered stable here include `Cell::update`,
`HashMap::extract_if`, `HashSet::extract_if`,
`core::hint::select_unpredictable`, and slice `as_chunks` variants.

Release: <https://blog.rust-lang.org/2025/06/26/Rust-1.88.0/>

## Rust 1.89

### Required review: raw-pointer implicit borrows

`dangerous_implicit_autorefs` moved from warn-by-default to deny-by-default.
Code that implicitly forms a Rust reference while operating through raw
pointers can therefore stop compiling.

Prefer explicit raw operations and `&raw const` / `&raw mut` where the
algorithm does not actually require a reference invariant.

### Target review: wasm C ABI

The `extern "C"` ABI on `wasm32-unknown-unknown` became standards-compliant.
If a project exchanges C-ABI values with separately compiled wasm/C code, test
that boundary rather than assuming the old Rust-specific behavior.

### Useful capability: inferred const-generic arguments

`_` can now be used for const-generic arguments when context determines the
value.

Release: <https://blog.rust-lang.org/2025/08/07/Rust-1.89.0/>

## Rust 1.90

### Required review: LLD is the default Linux x86-64 linker

`x86_64-unknown-linux-gnu` now uses LLD by default. Most projects only get
faster linking, but projects with custom linker scripts, unusual native
libraries, linker plugins, or linker-specific flags should exercise their real
link path.

Do not preemptively opt out. If there is an incompatibility, fix or isolate it;
`-C linker-features=-lld` exists as a compatibility escape hatch.

### Release engineering: workspace publishing

`cargo publish --workspace` can publish workspace crates in dependency order.
Publication is still not atomic, so release automation must still handle a
partially published workspace after network/server failure.

### Platform support: Intel macOS

`x86_64-apple-darwin` became Tier 2 with host tools. Rust still distributes
the toolchain, but the target no longer receives Tier-1 test guarantees.

Release: <https://blog.rust-lang.org/2025/09/18/Rust-1.90.0/>

## Rust 1.91

### Required review: dangling raw pointers from locals

The new warn-by-default `dangling_pointers_from_locals` lint catches functions
that return a raw pointer into a local value that is destroyed at function exit.
Fix these as lifetime/ownership bugs; the fact that creating the raw pointer is
not itself UB does not make the returned pointer useful.

### Numeric APIs

The `strict_*` integer arithmetic family stabilized. These operations panic on
overflow regardless of the ordinary overflow-check configuration, which can be
useful when overflow must be a runtime failure rather than build-profile
dependent.

### Platform support

`aarch64-pc-windows-msvc` became Tier 1.

Release: <https://blog.rust-lang.org/2025/10/30/Rust-1.91.0/>

## Rust 1.92

### Required review: never-type fallback

`never_type_fallback_flowing_into_unsafe` and
`dependency_on_unit_never_type_fallback` became deny-by-default. Code relying
on historical `!` → `()` fallback inference may stop compiling.

Fix the type inference explicitly. This is future-compatibility work for the
never type and should not be papered over with broad lint allowances.

### `panic = "abort"` changes on Linux

Linux builds now emit unwind tables by default even with `panic = "abort"`,
restoring useful backtraces. If binary-size work deliberately depended on their
absence, measure again and explicitly use `-Cforce-unwind-tables=no` only when
that tradeoff is intended.

### Attribute validation

Rust continues tightening built-in attribute validation; malformed
`#[macro_export]` input can now fail where older compilers accepted it.

Release: <https://blog.rust-lang.org/2025/12/11/Rust-1.92.0/>

## Rust 1.93

### Required review: musl 1.2.5

Bundled musl moved to 1.2.5. This improves resolver behavior but removes legacy
compatibility symbols used by sufficiently old versions of the `libc` crate.
The ecosystem fix shipped in `libc 0.2.146`; musl users should ensure they are
not pinned below it.

Networking-heavy static binaries should get explicit DNS/integration coverage
because the resolver implementation changed materially.

### Unsafe/memory APIs

Useful stable APIs include slice `MaybeUninit` initialization helpers plus
`String::into_raw_parts` and `Vec::into_raw_parts`. Prefer these APIs over
locally re-deriving allocation internals.

### Inline assembly

Individual `asm!` statements can now carry `#[cfg]`, reducing duplicated
architecture/feature-specific assembly blocks.

Release: <https://blog.rust-lang.org/2026/01/22/Rust-1.93.0/>

## Rust 1.94

### Required review: TOML 1.1 creates a development-MSRV distinction

Cargo 1.94 accepts TOML 1.1 syntax in manifests and Cargo configuration. A
repository that starts using TOML-1.1-only syntax now requires Cargo 1.94+ to
parse its source manifest even if the Rust source and declared
`package.rust-version` support an older compiler.

For crates published to a registry, Cargo rewrites the published manifest for
older parsers. That means these can legitimately differ:

- the **crate MSRV** promised to downstream registry consumers;
- the **development/source MSRV** required to clone and build the repository.

Applications, git dependencies, unpublished workspaces, and third-party tools
that parse `Cargo.toml` do not get the registry rewrite. Document the higher
source floor if you adopt TOML 1.1 syntax.

### Useful APIs

`<[T]>::array_windows` gives fixed-size array references while iterating
windows. `LazyCell` and `LazyLock` gained direct get/get_mut accessors.

Release: <https://blog.rust-lang.org/2026/03/05/Rust-1.94.0/>

## Rust 1.95

### Compile-time configuration: `cfg_select!`

`cfg_select!` selects the first matching compile-time cfg arm. It can replace
straightforward `cfg-if` usage, but ordering matters when predicates overlap.
Rust 1.99 later adds an `unused`-group lint for unreachable
`cfg_select!` predicates, so keep specific arms before broader arms.

### Pattern matching: `if let` guards

Match arms can use `if let PAT = EXPR` guards. Bindings from the guard are
available in the arm body, but the guard pattern does **not** contribute to
exhaustiveness checking; retain the fallback arm that makes the outer match
exhaustive.

### Required review: custom JSON target specifications

Passing custom JSON target specs to stable rustc was de-stabilized. Projects
building custom targets already needed nightly for other pieces of
`build-std`, but scripts that happened to pass a JSON target to stable must
move to an explicitly nightly/custom-target workflow.

Release: <https://blog.rust-lang.org/2026/04/16/Rust-1.95.0/>

## Rust 1.96

### New range types

`core::range::Range` and related replacement range types are copyable because
they implement `IntoIterator` rather than being iterators themselves. Range
syntax such as `0..10` still constructs the legacy range types in this
release line.

For public APIs that can accept either representation, prefer
`impl RangeBounds<_>` rather than unnecessarily locking callers to one concrete
range type.

### Testing

`assert_matches!` and `debug_assert_matches!` are stable. They are not in the
prelude, so import them from `core` or `std`.

### Required review: WebAssembly undefined symbols

WebAssembly linking no longer implicitly turns undefined symbols into
`"env"` imports via `--allow-undefined`. Missing symbols are link errors.
Declare intended imports explicitly; only restore the old linker flag when the
undefined-import model is genuinely the desired ABI.

Release: <https://blog.rust-lang.org/2026/05/28/Rust-1.96.0/>

## Rust 1.97

### Required review: symbol mangling v0

The v0 Rust symbol-mangling scheme became the stable default. Tools that inspect
raw symbols, maintain allowlists by mangled name, post-process profiles, or use
custom demanglers should be tested. Normal Rust linking should not require
source changes.

### CI: use Cargo-native warning denial

Cargo can now control whether warnings fail a local package build:

```bash
CARGO_BUILD_WARNINGS=deny cargo check --locked --workspace --all-targets
```

Prefer this over `RUSTFLAGS=-Dwarnings` when the only goal is CI warning
policy. Changing `RUSTFLAGS` changes compiler flags and build-cache identities;
Cargo's warning policy does not need to invalidate the underlying cached build
for that reason.

This does not replace a deliberate source lint policy in
`[lints.rust]` / `[lints.clippy]`.

### Required review: linker messages become visible

Successful linker invocations can now surface `linker_messages`. This lint is
special and is not part of rustc's ordinary `warnings` lint group. Treat newly
visible linker output as platform-sensitive evidence to investigate, not a
reason for a blanket global allow.

Release: <https://blog.rust-lang.org/2026/07/09/Rust-1.97.0/>

## Rust 1.98 / 1.98.1

### Required review: stricter FFI/layout checking

Rust 1.98 added deny-by-default `invalid_runtime_symbol_definitions` and
warn-by-default `suspicious_runtime_symbol_definitions`, initially covering
runtime symbols such as `memcpy`, `memset`, and `strlen`.
`c_void_returns` also warns on using `core::ffi::c_void` as a Rust return
type.

`repr(transparent)` validation became stricter about which additional fields
count as layout-trivial, and several ambiguous-import/layout/transmute cases
that older compilers accepted are now rejected or diagnosed more strongly.
Re-run ABI/layout tests rather than merely making the code compile.

### Performance and parser APIs

High-value additions include:

- `core::fmt::NumBuffer` and primitive integer `format_into`;
- `str::substr_range` and `[T]::subslice_range`;
- `f32` / `f64` `algebraic_*` operations as an explicit relaxed arithmetic
  contract;
- `Atomic<T>::from_mut` and slice variants.

Use the algebraic floating-point APIs only when reassociation/non-reproducible
rounding is within the numerical contract.

### Patch release

Rust 1.98.1 fixed a rustc vtable-generation miscompilation. Do not pin a project
to 1.98.0 when remaining on the 1.98 release line.

Release: <https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/>

## Rust 1.99

### Required review: Edition-2024 inherited `default-features`

Cargo 1.99 makes this effective for Edition 2024+ workspace members:

```toml
# workspace root
[workspace.dependencies]
serde = { version = "1", features = ["derive"] }

# Edition-2024 member
[dependencies]
serde = { workspace = true, default-features = false }
```

On Cargo 1.85–1.98 the member-level `default-features = false` was ignored
with a warning. On 1.99 it disables the dependency's default features even if
the workspace declaration left them enabled.

This is the most important Cargo semantic migration in 1.99 because a
toolchain-only bump can change the compiled feature graph. Search the workspace
for inherited dependencies carrying `default-features = false` and test those
members' feature matrices before merging.

### CI behavior: incremental compilation

Cargo 1.99 disables incremental compilation by default when the `CI`
environment variable is present. Revisit cache expectations and CI timing
baselines; do not assume an existing target-directory cache still contains
useful incremental state.

Cargo also adds a built-in `debug` profile. In 1.99 it is equivalent to
`dev`; it exists to allow future development-profile defaults to evolve
without conflating “fast iteration” with “debuggable build”.

### FFI: stable C-variadic definitions

Rust can now define variadic functions using the `"C"` and `"C-unwind"`
ABIs:

```rust
unsafe extern "C" fn first_i32(mut args: ...) -> i32 {
    // SAFETY: caller contract guarantees a compatible i32 argument exists.
    unsafe { args.next_arg::<i32>() }
}
```

The variadic parameter is `core::ffi::VaList<'_>`. Reading it remains unsafe:
the caller controls how many arguments exist and their actual C-promoted types.
Treat a count/tag/format string or equivalent foreign contract as part of the
safety proof.

### Unsafe code: layout from raw pointers

`size_of_val_raw`, `align_of_val_raw`, and `Layout::for_value_raw` let code
query layout from a raw pointer, including DST metadata, without creating an
intermediate Rust reference. They remain unsafe because the raw pointer's
metadata must satisfy each API's documented requirements.

This is especially useful in allocators, DST containers, FFI, and other code
that previously created a reference solely to ask for layout.

### Unsafe code: raw-borrow lint

The new allow-by-default `raw_borrows_via_references` lint detects references
that immediately decay into raw pointers. Unsafe-heavy projects should consider
enabling it during migration and replacing unnecessary intermediate references
with direct `&raw const` / `&raw mut` borrows.

### Ownership: do not leak and later “unleak”

The `Box::leak` documentation now recommends against leaking an allocation and
later reconstructing ownership to free it. For temporary raw ownership
handoffs, use `Box::into_non_null` and `Box::from_non_null` with an explicit
single-owner safety invariant.

The same principle applies to other standard-library leak helpers: leaking
should mean intentionally giving up automatic destruction for the requested
lifetime, not an ownership-conversion trick.

### Compatibility checks worth running

Rust 1.99 also:

- makes `no_mangle_generic_items` a hard error;
- fully deprecates legacy integral modules such as `std::i32::MAX`;
- extends runtime-symbol diagnostics to POSIX symbols, including ABI checking of imports/definitions such as POSIX `open` (whose canonical signature is variadic);
- adds `unreachable_cfg_select_predicates` to the `unused` lint group;
- extends `unconditional_panic` to zero-size `chunks` / `windows` calls;
- can surface semicolon-in-expression warnings originating from macros in other
  crates;
- changes some non-guaranteed observations of an already-exhausted legacy
  `RangeInclusive` iterator.

Release: <https://blog.rust-lang.org/2026/10/01/Rust-1.99.0/>

## Final migration checklist

A 1.88 codebase is ready to call its normal toolchain “1.99” when all of the
following are true:

1. A locked dependency graph passes check, Clippy, tests, doctests/docs, and
   required target builds on 1.99.0.
2. New compiler diagnostics were fixed or narrowly justified rather than
   blanket-allowed.
3. Edition-2024 inherited `default-features = false` declarations were audited
   for the Cargo 1.99 behavior change.
4. Linux x86-64 native/linker tests pass under LLD.
5. Any musl build uses a sufficiently new `libc` and has networking coverage
   appropriate to the application.
6. WebAssembly projects explicitly model intended imports.
7. FFI/layout/raw-pointer code was reviewed under the 1.98–1.99 diagnostics and
   new raw-layout APIs.
8. Leak→unleak ownership tricks were replaced with ownership-preserving raw
   APIs.
9. CI caching does not depend on Cargo incremental compilation being enabled
   merely because the target directory is cached.
10. The declared MSRV was changed only if the project intentionally changed its
    compatibility contract, not merely because normal development moved to
    1.99.

## Primary sources

- Rust release announcements:
  <https://blog.rust-lang.org/releases/>
- Detailed Rust release notes:
  <https://doc.rust-lang.org/releases.html>
- Cargo changelog:
  <https://doc.rust-lang.org/nightly/cargo/CHANGELOG.html>
- Rust Reference, C-variadic functions:
  <https://doc.rust-lang.org/reference/items/functions.html#c-variadic-functions>
