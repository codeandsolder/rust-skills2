# unsafe-untrusted-safe-code

> Never make memory safety depend on the correctness of a safe trait implementation, callback, or other caller-controlled safe behavior

## Why It Matters

A safe caller can implement a safe trait incorrectly, return different values on repeated calls, panic, or leak an object. Such behavior may violate a logical contract, but it must not turn a call to a safe API into undefined behavior. An unsafe abstraction must enforce its own memory-safety preconditions or rely on a relevant, explicitly documented unsafe contract.

## Bad: Validate One Result and Use Another

Checking the length of one `AsRef<[T]>::as_ref()` result does not establish the length of a later result. The implementation can switch between slices using interior mutability. Checking the second slice with ordinary safe indexing is sound; using unchecked indexing based on the first slice is not.

Similarly, `Iterator::size_hint()` and `ExactSizeIterator::len()` are not proofs of how many initialized values have actually arrived. Reserve using a hint if appropriate, but track initialized elements and enforce bounds independently.

## Good: Validate and Use the Same Value

<!-- rust-check: run -->
```rust
use std::cell::Cell;

fn checked_get(input: &impl AsRef<[u8]>, index: usize) -> Option<u8> {
    let bytes = input.as_ref();
    bytes.get(index).copied()
}

struct Alternating {
    calls: Cell<usize>,
}

impl AsRef<[u8]> for Alternating {
    fn as_ref(&self) -> &[u8] {
        let count = self.calls.get();
        self.calls.set(count + 1);
        if count % 2 == 0 { &[10, 20] } else { &[] }
    }
}

fn main() {
    let input = Alternating { calls: Cell::new(0) };
    assert_eq!(checked_get(&input, 1), Some(20));
    assert_eq!(input.calls.get(), 1);
    assert_eq!(checked_get(&input, 1), None);
    assert_eq!(input.calls.get(), 2);
}
```

If unchecked access actually improves measured performance, prove the bounds, lifetime and any other preconditions using that same retained slice. Do not add unsafe operations to an already adequate checked implementation.

## Trust Boundaries

- Safe trait contracts such as `Ord`, `Hash`, `Clone`, `AsRef` and `ExactSizeIterator` can support normal logical behavior but cannot justify unchecked memory access.
- An unsafe trait, such as nightly `TrustedLen`, can provide a specific safety guarantee if its contract matches the operation exactly. Do not invent an unsafe trait just to avoid inexpensive validation.
- Foreign code, external state, callbacks and concurrent mutations require appropriate synchronization, ownership and validation; checking a value does not freeze unrelated state.
- Even safe `mem::forget` can suppress destructors. A guard must leave a sound state if leaked; cleanup is not a soundness proof.
- Test malicious or buggy *safe* implementations (changing results, mismatched length hints, panics) against the safe public boundary, not only the intended implementation.

## See Also

- [unsafe-unwind-safety](./unsafe-unwind-safety.md) — interrupted operations
- [unsafe-safety-comment](./unsafe-safety-comment.md) — proof obligations
- [unsafe-miri-ci](./unsafe-miri-ci.md) — exercise unsafe boundaries
- [Rustonomicon: Safe and Unsafe Meaning](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html)
- [ExactSizeIterator](https://doc.rust-lang.org/std/iter/trait.ExactSizeIterator.html)
