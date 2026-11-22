# proj-nightly-features

> Use a dated nightly when a specific unstable feature earns its maintenance cost; track feature gates and remove them when the required API stabilizes

## Why It Matters

Nightly can eliminate substantial bespoke code (portable SIMD, typed const computation, local try contexts, specialized low-level APIs). It is not a compatibility layer: unstable semantics, standard-library APIs, and compiler diagnostics can change between builds. Keep the stable baseline separate from the nightly compiler used by CI; a future stabilization recorded in nightly source is not available on the current stable release.

## Current feature guide

Verified against Rust 1.102.0-nightly (bdf712ee87, 2026-11-21), compared with Rust 1.100.0. This is a curated selection, not every experimental gate.

| Feature gate | When to consider it | Important constraint |
|---|---|---|
| `portable_simd` | Cross-ISA vector kernels | Explicit arithmetic, mask, tail and FP semantics; see [opt-simd-portable](opt-simd-portable.md) |
| `try_blocks` | Expression-local propagation | Homogeneous try context; distinct from heterogeneous try-block experiment |
| `try_trait_v2` | A custom propagation abstraction | Preserve the residual's meaning; ordinary `?` needs no feature gate |
| `likely_unlikely` | Measured branch probabilities | These are hints, not guarantees; stable `cold_path()` is often sufficient |
| `iter_collect_into` | Append an iterator into an existing collection | Does not clear the destination; `Extend::extend` is stable |
| `array_try_from_fn`, `array_try_map` | Fallible fixed-size initialization/transformation | Distinguish early error from partial initialization |
| `generic_const_exprs`, `generic_const_items`, `gca_min_const_items`, `gca_adts`, `function_arg_const_generics` | Generic compile-time computation and richer const parameters | Several overlapping incomplete experiments; do not assume interchangeability or soundness of arbitrary expressions |
| `const_trait_impl` and individual const library gates | Generic compile-time trait calls | Both trait and called operations must support const evaluation |
| `default_field_values`, `type_changing_struct_update` | Less construction boilerplate | Respect invariants and visibility; do not confuse with stable const-generic defaults |
| `return_type_notation`, `async_fn_in_dyn_trait` | Async trait bounds or dynamic dispatch | Experimental, distinct from stable async methods in traits |
| `gen_blocks`, `coroutines` | Lazy generators or suspension-based state machines | Distinct features and contracts; prefer explicit iterators when already simple |
| `must_not_suspend`, `strict_provenance_lints` | Additional compiler diagnostics | Opt-in and scope-specific; useful for async guards or low-level pointer code |
| `explicit_tail_calls` | Deliberate tail-call control flow | Restricted calling/return conventions; no automatic TCO promise |
| `optimize_attribute` | Per-function optimization goals | Accepted for 1.101 according to compiler source; remove the gate once that is the actual project baseline |

## Newly visible library features worth evaluating

These gates appear in the nightly library source but not the 1.100 source inventory. Consult the exact API and tracking issue before adoption.

| Gate / API | Use and boundary |
|---|---|
| `rename_noreplace` ([#161427](https://github.com/rust-lang/rust/issues/161427)) | `std::fs::rename_noreplace` avoids check-then-rename races; handle AlreadyExists / Unsupported and platform/filesystem differences |
| `get_set_bit` ([#147702](https://github.com/rust-lang/rust/issues/147702)) | Integer `bit` / `set_bit`; the latter returns a new integer; validate or prove index bounds |
| `maybe_uninit_from_ref` ([#165213](https://github.com/rust-lang/rust/issues/165213)) | `MaybeUninit::from_ref` borrows initialized storage without a handwritten reinterpretation |
| `mpsc_channel_len` ([#165247](https://github.com/rust-lang/rust/issues/165247)) | Channel length/emptiness for monitoring; a concurrent snapshot is not a synchronization or admission-control guarantee |
| `float_mul_add_relaxed` ([#151770](https://github.com/rust-lang/rust/issues/151770)) | Allows fused or separate multiply/add; unsuitable when exact rounding or reproducibility is required |
| `fd_view` ([#160402](https://github.com/rust-lang/rust/issues/160402)) | Borrow a typed descriptor/handle view; preserve ownership and lifetime contracts |
| `discriminant_ord` ([#165438](https://github.com/rust-lang/rust/issues/165438)) | Order enum discriminants; the ordering is not a stable serialization protocol |
| `byte_str`, `byte_str_to_string` | Byte-oriented string APIs; renamed from the `bstr` family, so recheck feature flags and conversions rather than assuming source compatibility |
| `vec_repeat` ([#164215](https://github.com/rust-lang/rust/issues/164215)) | Repeated vector elements including allocator-aware construction; compare with stable `vec![value; n]` |

## Stabilization watchlist

The 1.102 nightly library records stabilization of the following for 1.101; feature flags are unnecessary once the toolchain actually supports those stable APIs. Do not raise a project's compiler baseline merely to silence a diagnostic.

- `Result::into_ok` / `into_err` (`unwrap_infallible`): extract from an infallible result without a panic path.
- `Vec::try_remove`: checked removal without an indexing panic.
- `Arc::is_unique` / `Rc::is_unique`: uniqueness checks; not equivalent to a general proof based on an arbitrary reference count snapshot.
- `[T]::split_once` / `rsplit_once`: split at the first/last matching element.
- Integer funnel shifts: prefer the native operations when the two-word shift semantics match.
- Other source-level stabilization changes include `cstr_display`, `debug_closure_helpers`, `exclusive_wrapper`, `int_from_ascii`, `pointer_try_cast_aligned`, `ptr_cast_slice`, `string_into_chars`, and const collection length APIs.

## Toolchain and verification

- Pin a dated nightly in `rust-toolchain.toml` when a project actually uses unstable features. Install the needed targets/components; validate on that same compiler in CI.
- Enable only the gates the code requires. Do not use `RUSTC_BOOTSTRAP` to pretend a stable toolchain supports them.
- Check new, accepted and removed compiler features at the exact rustc commit; inspect library stability attributes and the actual rustdoc method signature. Gate names in a historical example are not proof of current availability.
- Keep nightly examples separate from stable compile contracts; compile and exercise nightly-only behavior with the pinned nightly before using it.
- Review the [Unstable Book](https://doc.rust-lang.org/nightly/unstable-book/) and [nightly standard library](https://doc.rust-lang.org/nightly/std/) and their linked tracking issues; internal features are not general-purpose public APIs.

## See Also

- [proj-msrv-declare](proj-msrv-declare.md) — distinguish project baseline and compiler choice
- [const-generics](const-generics.md) — stable const generics
- [err-try-block-experimental](err-try-block-experimental.md) — local try contexts
- [opt-simd-portable](opt-simd-portable.md) — vectorization
- [unsafe-miri-ci](unsafe-miri-ci.md) — nightly Miri for unsafe code
