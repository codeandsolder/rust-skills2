# unsafe-minimize-scope

> Keep unsafe operations local, but make the safe boundary enforce every precondition; small unsafe blocks alone do not establish soundness

## Why It Matters

An `unsafe fn` communicates caller obligations, whereas an `unsafe {}`
block identifies an operation the author must justify. The two are not
interchangeable. In Edition 2024, `unsafe_op_in_unsafe_fn` warns on an
implicit unsafe operation; shared strict CI denies that lint.

## Bad: A Safe Raw-Pointer API Without a Validity Proof

A safe function taking a raw pointer and a length must not dereference
the pointer merely because an index is below that length. Safe callers
can provide null, dangling, misaligned or otherwise invalid pointers.
Neither a bounds check nor a small unsafe block fixes the missing
contract. Never demonstrate the resulting undefined behavior by running it.

## Good: Use a Safe Borrow Where Possible

<!-- rust-check: run -->
```rust
fn read_at(values: &[i32], index: usize) -> Option<i32> {
    values.get(index).copied()
}

fn main() {
    assert_eq!(read_at(&[4, 5], 1), Some(5));
    assert_eq!(read_at(&[4, 5], 2), None);
    assert_eq!(read_at(&[], 0), None);
}
```

## Good: Keep a Real Raw-Pointer Contract Explicit

<!-- rust-check: run -->
```rust
/// # Safety
///
/// If index is below len, ptr must point to a live, aligned, initialized
/// range of len i32 values within one allocation, valid for shared reads
/// for this call. The range must not conflict with concurrent writes.
unsafe fn raw_read_at(ptr: *const i32, len: usize, index: usize) -> Option<i32> {
    if index >= len {
        return None;
    }
    // SAFETY: the caller guarantees the range; the check selects an element.
    Some(unsafe { *ptr.add(index) })
}

fn main() {
    let values = [4, 5];
    // SAFETY: values is live and initialized for the call.
    assert_eq!(unsafe { raw_read_at(values.as_ptr(), values.len(), 1) }, Some(5));
    // SAFETY: index is outside the empty range; the pointer is not accessed.
    assert_eq!(unsafe { raw_read_at(std::ptr::null(), 0, 0) }, None);
}
```

At real FFI boundaries, additionally satisfy the complete foreign ABI and
ownership contract. Prefer a safe slice internally, rather than repeatedly
checking raw pointers throughout the algorithm.

## Scope and Proof

- Separate genuinely unsafe operations from unrelated safe logic.
- Group adjacent operations when they share one invariant and a single
  proof is clearer than repeated comments.
- Keep the check and operation linked to the same value and lifetime.
- Use checked indexing unless measurement and a complete proof justify
  the unchecked alternative.
- Consider failures, unwinding and safe callers that violate logical
  (but not unsafe) contracts.

## See Also

- [unsafe-safety-comment](./unsafe-safety-comment.md)
- [unsafe-untrusted-safe-code](./unsafe-untrusted-safe-code.md)
- [unsafe-unwind-safety](./unsafe-unwind-safety.md)
- [unsafe-ffi-boundary](./unsafe-ffi-boundary.md)
