# unsafe-extern-block

> In Rust 2024, use `unsafe extern { }` blocks and mark an item `safe` only when every safe Rust caller can satisfy its contract.

## Why It Matters

Before Rust 2024, every function declared inside an `extern "C" { }` block was implicitly unsafe to call, while the block itself carried no `unsafe` keyword. Rust 2024 makes the declaration boundary explicit: the block must be `unsafe extern`, signaling that the programmer is responsible for declaring the external ABI accurately.

Items remain unsafe by default. Marking an item `safe` is a much stronger promise: **all values expressible by its Rust signature must be valid inputs for the foreign function**. Raw-pointer APIs with validity, lifetime, aliasing, initialization, or null-termination preconditions should therefore normally remain `unsafe` and be wrapped by a separately implemented safe Rust API.

## Bad

<!-- rust-check: compile_fail; reason=Edition 2024 requires extern blocks to be unsafe -->
```rust
// Rust 2021 style — forbidden in the 2024 edition
extern "C" {
    fn strlen(s: *const std::ffi::c_char) -> usize;
    fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8;
}
```

```rust
// UNSOUND: safe Rust callers can pass null, dangling, overlapping,
// or otherwise invalid pointers.
unsafe extern "C" {
    pub safe fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8;
}
```

## Good

```rust
unsafe extern "C" {
    // Caller must provide a valid NUL-terminated C string.
    pub unsafe fn strlen(s: *const std::ffi::c_char) -> usize;

    // Caller must provide valid, non-overlapping regions of at least n bytes.
    pub unsafe fn memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8;

    // Hypothetical function whose complete contract really is represented by
    // its Rust signature. Only such items should be declared `safe`.
    pub safe fn rust_version_major() -> u32;

    // Access to an extern static may rely on initialization, validity,
    // synchronization, mutability, and other foreign-code invariants.
    pub unsafe static errno: std::ffi::c_int;
}

// If the Rust API accepts raw pointers, preserve the caller-side contract.
/// Copies `n` bytes from `src` to `dst`.
///
/// # Safety
/// `src` and `dst` must each be valid for `n` bytes and must not overlap.
unsafe fn copy_bytes(dst: *mut u8, src: *const u8, n: usize) {
    // SAFETY: forwarded directly from this function's documented preconditions.
    unsafe { memcpy(dst, src, n) };
}

// Prefer a genuinely safe wrapper when Rust types can establish the contract.
fn copy_slice(dst: &mut [u8], src: &[u8]) {
    assert_eq!(dst.len(), src.len());
    // Distinct Rust borrows establish valid, non-overlapping regions.
    unsafe { memcpy(dst.as_mut_ptr(), src.as_ptr(), src.len()) };
}
```

## Migration from 2021

| 2021 | 2024 |
|------|------|
| `extern "C" { fn foo(); }` | `unsafe extern "C" { unsafe fn foo(); }` |
| `extern "C" { fn bar(); }` where every call is safe | `unsafe extern "C" { safe fn bar(); }` |
| `extern "C" { static X: i32; }` | `unsafe extern "C" { unsafe static X: i32; }` |

Run `cargo fix --edition` for the mechanical syntax migration, then review every declaration's actual safety contract. Do not convert items to `safe` merely to remove `unsafe` blocks at call sites.

## Key Points

- `unsafe` on the block means the declarations themselves are trusted to match the foreign ABI.
- An `unsafe` item may impose caller obligations; document them and expose a safe wrapper only when the wrapper establishes them.
- A `safe` extern item must be safe for every call permitted by its Rust signature.
- Raw pointers in a signature are not automatically unsafe, but any unchecked validity, aliasing, lifetime, initialization, or provenance requirement is a strong sign that the item must remain `unsafe`.
- Extern statics require the same careful invariant analysis; data races are only one possible source of unsoundness.

## See Also

- [unsafe-no-mangle-unsafe](unsafe-no-mangle-unsafe.md) - mark `#[no_mangle]` as `#[unsafe(no_mangle)]` in Rust 2024
- [type-repr-transparent](type-repr-transparent.md) - layout guarantees for intentional transparent wrappers
