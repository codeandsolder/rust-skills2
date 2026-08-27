# doc-safety-section

> Document caller obligations with `# Safety`; justify local unsafe operations with `// SAFETY:` proofs

## Why It Matters

An `unsafe fn` moves part of Rust's safety proof from the compiler to the caller. Its documentation must state the conditions a caller has to uphold so that calling the function is sound.

That public contract is different from the proof inside an `unsafe { ... }` block. A local `// SAFETY:` comment should explain why the code at that point satisfies the relevant unsafe operation's preconditions.

## Good: State the Caller's Preconditions

```rust
/// Reads one byte from `ptr`.
///
/// # Safety
///
/// The caller must ensure that `ptr`:
/// - is non-null and valid for reading one initialized `u8`;
/// - remains valid for the duration of this call; and
/// - is not involved in a concurrent conflicting access.
pub unsafe fn read_byte(ptr: *const u8) -> u8 {
    // SAFETY: these are exactly the preconditions required from the caller.
    unsafe { ptr.read() }
}

fn main() {
    let byte = 7_u8;
    // SAFETY: `&byte` provides a valid initialized address for this call.
    assert_eq!(unsafe { read_byte(&byte) }, 7);
}
```

Do not merely write “caller must call this safely.” Name the validity, lifetime, aliasing, initialization, layout, or protocol requirements that cannot be checked by the type system.

## Unsafe Blocks in Safe APIs Need Local Proofs

A safe function must not require hidden caller preconditions. Its unsafe block is an implementation detail whose proof follows from safe inputs and checks performed by the function.

```rust
pub fn get<T>(slice: &[T], index: usize) -> Option<&T> {
    if index < slice.len() {
        // SAFETY: the bounds check above proves `index < slice.len()`.
        Some(unsafe { slice.get_unchecked(index) })
    } else {
        None
    }
}

fn main() {
    assert_eq!(get(&[10, 20], 1), Some(&20));
    assert_eq!(get(&[10, 20], 2), None);
}
```

A public `# Safety` section would be misleading here because callers have no unsafe obligation.

## Unsafe Traits Document Implementor Obligations

For an unsafe trait, document what an `unsafe impl` promises. Then justify each implementation where the proof is not self-evident.

```rust
/// Types for which the all-zero bit pattern is a valid value.
///
/// # Safety
///
/// Implementors must guarantee that a value consisting entirely of zero bits
/// is a valid initialized instance of `Self`.
pub unsafe trait Zeroable: Sized {
    fn zeroed() -> Self;
}

// SAFETY: every bit pattern is valid for `u32`, including all-zero bits.
unsafe impl Zeroable for u32 {
    fn zeroed() -> Self {
        0
    }
}

fn main() {
    assert_eq!(u32::zeroed(), 0);
}
```

Do not invent extra requirements such as “contains no pointers” or “has no padding” unless the abstraction actually depends on those properties. Safety documentation should state the minimal real invariant.

## Edition 2024: `unsafe extern` Applies to External Blocks

Edition 2024 requires **external declaration blocks** to be written `unsafe extern`. The `unsafe` marks the author's responsibility for declaring the foreign signatures correctly.

```rust
use core::ffi::{c_char, c_int};

unsafe extern "C" {
    /// Absolute value from the C runtime.
    pub safe fn abs(value: c_int) -> c_int;

    /// Returns the length of a NUL-terminated C string.
    ///
    /// # Safety
    ///
    /// `ptr` must point to a valid NUL-terminated byte string readable through
    /// the terminating NUL byte.
    pub unsafe fn strlen(ptr: *const c_char) -> usize;
}
```

Items in an unsafe extern block are unsafe to call by default. Edition 2024 also allows an item whose declaration is genuinely safe for all Rust values to be marked `safe`, as with `abs` above.

This is separate from defining a Rust function with a foreign ABI:

```rust
/// Adds one to `value` using the C ABI.
//
// SAFETY: this crate owns the exported symbol name `rust_add_one`.
#[unsafe(export_name = "rust_add_one")]
pub extern "C" fn add_one(value: i32) -> i32 {
    value.saturating_add(1)
}
```

`pub unsafe extern "C" fn ...` remains the syntax for a **defined unsafe function** using a foreign ABI. `unsafe extern "C" { ... }` is the syntax for an **external declaration block**. Do not conflate the two.

## Edition 2024 Unsafe Attributes

`no_mangle`, `export_name`, and `link_section` are unsafe attributes in Edition 2024 and must use the `#[unsafe(...)]` syntax. Their obligation belongs to the item author: for example, exported symbol names share a process-wide/link-wide namespace and must not collide incompatibly.

The unsafe attribute does not by itself make the function unsafe to call. Whether a function is `unsafe fn` depends on its caller-visible preconditions.

## Useful Lints

```rust
#![warn(clippy::missing_safety_doc)]
#![warn(clippy::undocumented_unsafe_blocks)]
```

- `missing_safety_doc` checks public unsafe APIs for caller-facing safety documentation.
- `undocumented_unsafe_blocks` checks for local explanations around unsafe operations.

Treat the comments as proofs, not ceremony. A stale or circular `SAFETY` comment is worse than a compiler warning because it gives reviewers false confidence.

## See Also

- [lint-unsafe-doc](./lint-unsafe-doc.md) — unsafe contracts and proof comments
- [doc-panics-section](./doc-panics-section.md) — documenting panics
- [doc-errors-section](./doc-errors-section.md) — documenting recoverable errors
