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
| `must_not_suspend`, `strict_provenance_lints` | Additional compiler diagnostics | Opt-in and scope-specific; the latter unlocks the implicit provenance casts lint; explicitly select the severity |
| `explicit_tail_calls` | Deliberate tail-call control flow | Restricted calling/return conventions; no automatic TCO promise |


## Newly visible library features worth evaluating

These gates appear in the nightly library source but not the 1.100 source inventory. Consult the exact API and tracking issue before adoption.

| Gate / API | Use and boundary |
|---|---|
| `rename_noreplace` ([#161427](https://github.com/rust-lang/rust/issues/161427)) | `std::fs::rename_noreplace` does not overwrite an existing destination; fallback may link then unlink, so do not promise atomic rename on every filesystem; handle AlreadyExists / Unsupported |
| `get_set_bit` ([#147702](https://github.com/rust-lang/rust/issues/147702)) | Integer `bit` / `set_bit`; the latter returns a new integer; validate or prove index bounds |
| `maybe_uninit_from_ref` ([#165213](https://github.com/rust-lang/rust/issues/165213)) | `MaybeUninit::from_ref` borrows initialized storage without a handwritten reinterpretation |
| `mpsc_channel_len` ([#165247](https://github.com/rust-lang/rust/issues/165247)) | Channel length/emptiness for monitoring; a concurrent snapshot is not a synchronization or admission-control guarantee |
| `float_mul_add_relaxed` ([#151770](https://github.com/rust-lang/rust/issues/151770)) | Allows fused or separate multiply/add; unsuitable when exact rounding or reproducibility is required |
| `fd_view` ([#160402](https://github.com/rust-lang/rust/issues/160402)) | Convert a borrowed descriptor or handle into a supported file-like reference via `to_view`; no ownership transfer, not arbitrary descriptor type validation |
| `discriminant_ord` ([#165438](https://github.com/rust-lang/rust/issues/165438)) | Order enum discriminants; the ordering is not a stable serialization protocol |
| `byte_str`, `byte_str_to_string` | Byte-oriented string APIs; renamed from the `bstr` family, so recheck feature flags and conversions rather than assuming source compatibility |
| `vec_repeat` ([#164215](https://github.com/rust-lang/rust/issues/164215)) | Repeated vector elements including allocator-aware construction; compare with stable `vec![value; n]` |

## Executable library API contracts

Use the actual public APIs, not signatures inferred from feature names.
The fallible array APIs preserve the callback's try context.

<!-- rust-check: nightly(array_try_from_fn,array_try_map); reason=fallible array construction and mapping -->
```rust
#![feature(array_try_from_fn, array_try_map)]

fn main() {
    let values: Option<[usize; 3]> = std::array::try_from_fn(|i| Some(i * 2));
    assert_eq!(values, Some([0, 2, 4]));

    let mut calls = 0;
    let parsed: Result<[u8; 3], _> = ["1", "bad", "3"].try_map(|s| {
        calls += 1;
        s.parse::<u8>()
    });
    assert!(parsed.is_err());
    assert_eq!(calls, 2);
}
```

<!-- rust-check: nightly(get_set_bit,maybe_uninit_from_ref,mpsc_channel_len,float_mul_add_relaxed,discriminant_ord,vec_repeat,byte_str,byte_str_to_string); reason=verify reviewed new library features -->
```rust
#![feature(get_set_bit, maybe_uninit_from_ref, mpsc_channel_len,
    float_mul_add_relaxed, discriminant_ord, vec_repeat, byte_str,
    byte_str_to_string)]

use std::{alloc::System, byte_str::ByteString, mem::{self, MaybeUninit},
    sync::mpsc};

fn main() {
    assert!(0_u8.set_bit(3, true).bit(3));
    assert_eq!(0_u8.set_bit(3, true), 8);

    let value = 42_u32;
    let storage: &MaybeUninit<u32> = MaybeUninit::from_ref(&value);
    assert_eq!(storage.as_ptr(), &raw const value);

    let (tx, rx) = mpsc::channel::<u8>();
    assert!(rx.is_empty());
    assert!(tx.send(7).is_ok());
    assert_eq!(rx.len(), 1);
    assert_eq!(rx.recv(), Ok(7));

    let (a, b, c) = (0.1_f64, 0.1_f64, -0.01_f64);
    let relaxed = a.mul_add_relaxed(b, c);
    assert!(relaxed == a.mul_add(b, c) || relaxed == a * b + c);

    enum Choice { First(u8), Second }
    let first = Choice::First(1);
    let another = Choice::First(2);
    assert!(mem::discriminant(&first).ord() == mem::discriminant(&another).ord());
    assert!(mem::discriminant(&first).ord() != mem::discriminant(&Choice::Second).ord());

    assert_eq!(Vec::repeat(7, 3), [7; 3]);
    assert_eq!(Vec::repeat_in(7, 3, System).as_slice(), &[7; 3]);
    assert_eq!(ByteString(b"hello".to_vec()).to_string().ok().as_deref(), Some("hello"));
    assert!(ByteString(vec![0xff]).to_string().is_err());
}
```

File operations and descriptor views depend on platform and filesystem.
Verify their signatures without moving any external file.

<!-- rust-check: nightly(rename_noreplace,fd_view); reason=compile-only filesystem and Unix descriptor contracts -->
```rust,no_run
#![feature(rename_noreplace, fd_view)]

use std::{fs, io, path::Path};

fn move_without_overwrite(from: &Path, to: &Path) -> io::Result<()> {
    fs::rename_noreplace(from, to)
}

#[cfg(unix)]
fn descriptor_metadata(fd: std::os::fd::BorrowedFd<'_>) -> io::Result<fs::Metadata> {
    fd.to_view::<fs::File>().metadata()
}

fn main() {}
```

## Stabilization watchlist

The 1.102 nightly library records stabilization of the following for 1.101; feature flags are unnecessary once the toolchain actually supports those stable APIs. Do not raise a project's compiler baseline merely to silence a diagnostic.

- `Result::into_ok` / `into_err` (`unwrap_infallible`): extract from an infallible result without a panic path; the other variant implements `Into<!>` (not merely any type that looks uninhabited).
- `Vec::try_remove`: checked removal without an indexing panic.
- `Arc::is_unique` / `Rc::is_unique`: uniqueness checks; not equivalent to a general proof based on an arbitrary reference count snapshot.
- `[T]::split_once` / `rsplit_once`: split at the first/last matching element.
- Unsigned integer funnel shifts: prefer the native operations when two-word shift semantics match. Counts must be below the bit width for predictable behavior (overflow-checked builds panic on larger counts); unchecked variants require that bound for safety.
- `#[optimize(...)]` (`optimize_attribute`): the language feature is accepted for 1.101 and already ungated on this nightly; verify supported arguments and optimization behavior.
- Other source-level stabilization changes include `cstr_display`, `debug_closure_helpers`, `exclusive_wrapper`, `int_from_ascii`, `pointer_try_cast_aligned`, `ptr_cast_slice`, `string_into_chars`, and const collection length APIs.

The following operations already compile without feature gates on the
reviewed nightly. The older pinned stable compiler does not yet provide them.

<!-- rust-check: nightly; reason=1.101 stabilizations verified on 1.102 nightly without feature gates -->
```rust
use std::{rc::Rc, sync::Arc};

#[optimize(size)]
fn shifted(left: u8, right: u8) -> u8 {
    left.funnel_shl(right, 4)
}

fn main() {
    let good: Result<u8, !> = Ok(7);
    let bad: Result<!, u8> = Err(9);
    assert_eq!(good.into_ok(), 7);
    assert_eq!(bad.into_err(), 9);

    let mut values = vec![1, 2, 3];
    assert_eq!(values.try_remove(1), Some(2));
    assert_eq!(values.try_remove(9), None);
    assert_eq!([1, 2, 3].split_once(|&n| n == 2), Some((&[1][..], &[3][..])));

    let arc = Arc::new(1);
    let rc = Rc::new(1);
    assert!(Arc::is_unique(&arc));
    assert!(Rc::is_unique(&rc));
    let weak = Arc::downgrade(&arc);
    assert!(!Arc::is_unique(&arc));
    drop(weak);
    assert!(Arc::is_unique(&arc));
    assert_eq!(shifted(0x12, 0x34), 0x23);
}
```

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
