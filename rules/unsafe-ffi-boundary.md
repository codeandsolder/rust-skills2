# unsafe-ffi-boundary

> Keep foreign ABI conversion and ownership contracts at a narrow adapter boundary; expose normal Rust domain types behind it

## Why It Matters

A foreign caller does not participate in Rust's borrow checker or type validity rules. A C-compatible signature alone does not guarantee that a pointer is live, initialized, aligned, or exclusively accessible. Keep the unsafe proof near the ABI and maintain the actual semantic operation in ordinary safe Rust.

## Good: Validate at the Boundary

<!-- rust-check: run -->
```rust
fn checked_sum(bytes: &[u8]) -> Option<u64> {
    bytes.iter().try_fold(0_u64, |sum, &byte| sum.checked_add(u64::from(byte)))
}

/// Sum a foreign byte buffer, returning false on invalid length or overflow.
///
/// # Safety
/// Unless the null/length checks reject the call, a nonempty input must
/// point to len initialized bytes in one live allocation, valid for
/// shared reads for this call. output must be aligned, valid for a u64
/// write and disjoint from input. No concurrent access may conflict
/// with the reads or write.
unsafe extern "C" fn sum_bytes(input: *const u8, len: usize, output: *mut u64) -> bool {
    if output.is_null() || len > isize::MAX as usize || (len != 0 && input.is_null()) {
        return false;
    }
    let bytes = if len == 0 {
        &[]
    } else {
        // SAFETY: the caller guarantees a valid shared byte range; length is bounded.
        unsafe { std::slice::from_raw_parts(input, len) }
    };
    let Some(sum) = checked_sum(bytes) else { return false };
    // SAFETY: caller guarantees output is aligned, writable and disjoint.
    unsafe { output.write(sum) };
    true
}

fn main() {
    let input = [2_u8, 3, 5];
    let mut sum = 0;
    // SAFETY: input and output are live, valid and disjoint for the call.
    assert!(unsafe { sum_bytes(input.as_ptr(), input.len(), &raw mut sum) });
    assert_eq!(sum, 10);
    // SAFETY: no input bytes accessed at length zero; output remains valid.
    assert!(unsafe { sum_bytes(std::ptr::null(), 0, &raw mut sum) });
    assert_eq!(sum, 0);
    // SAFETY: null output is rejected before any memory access.
    assert!(!unsafe { sum_bytes(input.as_ptr(), input.len(), std::ptr::null_mut()) });
    // SAFETY: nonempty null input is rejected before any memory access.
    assert!(!unsafe { sum_bytes(std::ptr::null(), 1, &raw mut sum) });
}
```

The null/size checks do not establish pointer validity. This remains an unsafe entry point. For exports, add an explicit externally supported symbol and a matching header or generated binding; the example focuses on the adapter and does not export a symbol.

## Boundary Checklist

- Use ABI-compatible types, explicit layout where appropriate, and validate incoming integers before constructing restricted Rust types such as enums or references.
- Document length units, null/empty cases, alignment, initialization, mutability, lifetime, thread access and callback reentrancy. Never create a reference to invalid memory merely to validate it.
- Specify ownership transfer and which module frees each allocation; supply a matching release operation. Do not reconstruct a `Vec`/ `Box` using an unrelated allocator or capacity.
- Do not pass ordinary Rust ABI objects, trait objects, or Rust-owned container representation across independently compiled libraries without a deliberately supported ABI. Prefer opaque handles and explicit functions.
- A non-unwinding ABI is not a panic recovery mechanism. Prevent unwinding across it, and separately define deliberate unwind containment if appropriate; use an unwind-supporting ABI only when both sides' contracts support it.
- Unregister callbacks and wait for outstanding uses before freeing callback state. Validate concurrency and lifetime contracts for teardown as well as normal calls.

Choose a small module or separate adapter crate according to the actual boundary. Do not reproduce the foreign interface throughout the application just because a binding generator produced it.

## See Also

- [unsafe-extern-block](./unsafe-extern-block.md)
- [mem-custom-allocator](./mem-custom-allocator.md)
- [unsafe-unwind-safety](./unsafe-unwind-safety.md)
- [Rustonomicon: FFI](https://doc.rust-lang.org/nomicon/ffi.html)
