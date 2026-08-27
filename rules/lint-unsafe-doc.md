# lint-unsafe-doc

**Rule**: `lint-unsafe-doc`

> Document every unsafe operation with the invariant that makes it sound

## Why It Matters

An `unsafe` block tells the compiler that the programmer has discharged safety obligations the type system cannot verify. A useful `// SAFETY:` comment records those obligations and, crucially, why they hold at that exact call site. This makes review and later refactoring much less dependent on reconstructing hidden assumptions.

Clippy's `undocumented_unsafe_blocks` lint checks for a safety comment associated with unsafe blocks and unsafe impls. Separately, in Edition 2024, rustc's `unsafe_op_in_unsafe_fn` lint is **warn-by-default**: unsafe operations inside an `unsafe fn` should still appear in explicit `unsafe { ... }` blocks. Projects may choose to raise either lint to `deny`.

## Configuration

```toml
[lints.clippy]
undocumented_unsafe_blocks = "deny"

[lints.rust]
unsafe_op_in_unsafe_fn = "deny"
```

Using `deny` here is a project policy choice; Edition 2024 itself sets `unsafe_op_in_unsafe_fn` to `warn`, not `deny`.

## Bad

```rust
unsafe fn byte_at(ptr: *const u8, index: usize) -> u8 {
    // The unsafe operation is implicit in the unsafe fn body and its
    // preconditions are not explained.
    *ptr.add(index)
}

fn main() {}
```

The function being `unsafe` shifts obligations to its caller, but it does not explain those obligations or why any individual operation in the body is valid.

## Good

```rust
#![deny(unsafe_op_in_unsafe_fn)]

/// Reads one byte at `index` from a raw byte buffer.
///
/// # Safety
///
/// `ptr.add(index)` must be in bounds of one allocated object, valid for a
/// read of one initialized byte, and remain valid for the duration of this
/// call.
unsafe fn byte_at(ptr: *const u8, index: usize) -> u8 {
    // SAFETY: the function's safety contract requires exactly the validity,
    // initialization, and in-bounds conditions needed by add+deref here.
    unsafe { *ptr.add(index) }
}

fn checked_byte(data: &[u8], index: usize) -> Option<u8> {
    if index >= data.len() {
        return None;
    }

    // SAFETY: the branch above proves index < data.len(), so the element is
    // in bounds; a shared slice also guarantees initialized readable storage.
    Some(unsafe { *data.get_unchecked(index) })
}

fn main() {
    let bytes = [10, 20, 30];
    assert_eq!(checked_byte(&bytes, 1), Some(20));
}
```

Do not use a `debug_assert!` as the only justification for an unsafe operation whose precondition must hold in release builds. If the proof is a bounds check, that check must actually execute in the configurations where the unsafe operation executes.

## What a Useful Safety Comment Says

A safety comment should connect the unsafe operation's documented preconditions to facts established by the surrounding code. Useful comments answer questions such as:

- Which pointer provenance, alignment, initialization, aliasing, or lifetime requirement matters here?
- Which preceding check or type invariant proves it?
- Which ownership transfer makes a reconstruction operation valid exactly once?
- Which synchronization invariant justifies an unsafe `Send` or `Sync` impl?

Avoid comments that merely restate the syntax, such as `// SAFETY: calling unsafe function`.

## Caller Contracts vs Local Proofs

For an `unsafe fn`, document caller obligations in a `# Safety` section. Inside its body, still explain why each unsafe operation follows from that contract plus local facts.

```rust
/// Reconstructs ownership of a box previously converted with `Box::into_raw`.
///
/// # Safety
///
/// `ptr` must be the still-owned result of exactly one `Box::into_raw` call
/// for `T`, and it must not already have been reconstructed or freed.
unsafe fn reclaim<T>(ptr: *mut T) -> Box<T> {
    // SAFETY: the caller contract supplies Box::from_raw's provenance and
    // unique-ownership requirements.
    unsafe { Box::from_raw(ptr) }
}

fn main() {
    let ptr = Box::into_raw(Box::new(7));
    // SAFETY: ptr came from Box::into_raw above and has not been reused.
    let value = unsafe { reclaim(ptr) };
    assert_eq!(*value, 7);
}
```

## Unsafe Impls

The proof for `unsafe impl Send` or `Sync` is about cross-thread invariants, not whether “all bit patterns” are valid. Explain why the type's representation, ownership, synchronization, and external resources satisfy the unsafe trait's contract. Prefer letting auto traits derive naturally when the fields already encode the right semantics.

## Keep Unsafe Blocks Small Enough to Review

A small unsafe block can make the proof boundary obvious, but “one unsafe operation per block” is not a semantic rule. Group operations when they share one invariant and separating them would obscure that invariant; split them when different obligations deserve separate proofs.

## See Also

- [doc-safety-section](./doc-safety-section.md) - `# Safety` in docs
- [lint-deny-correctness](./lint-deny-correctness.md) - Correctness lints
- [unsafe-send-sync-manual](./unsafe-send-sync-manual.md) - Manual `Send`/`Sync`
