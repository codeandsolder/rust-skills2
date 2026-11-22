# unsafe-unwind-safety

> Preserve memory safety and ownership invariants at every unwind, early return, cancellation and safe-leak boundary

## Why It Matters

Banning explicit panics does not eliminate all unwinding: user callbacks, indexing, arithmetic, dependencies and destructors can still panic. A partially initialized allocation or a temporarily invalid owner can become unsound when control exits before a final repair step. Test both ordinary errors and unwind paths.

## Bad: Commit Before Initialization

Changing a vector's length to include uninitialized elements before invoking a fallible or panicking producer permits its destructor to access invalid elements. Similarly, temporarily moving out an owner's field without leaving a valid replacement can leave the owner invalid if a callback unwinds.

## Good: Prefer a Safe Owner That Tracks Progress

<!-- rust-check: run -->
```rust
use std::cell::Cell;
use std::panic::{catch_unwind, AssertUnwindSafe};

struct Item<'a>(&'a Cell<usize>);

impl Drop for Item<'_> {
    fn drop(&mut self) {
        self.0.set(self.0.get() + 1);
    }
}

fn try_build<T, E>(
    count: usize,
    mut make: impl FnMut(usize) -> Result<T, E>,
) -> Result<Vec<T>, E> {
    let mut result = Vec::with_capacity(count);
    for index in 0..count {
        result.push(make(index)?);
    }
    Ok(result)
}

fn main() {
    let dropped = Cell::new(0);
    let result = try_build(5, |index| {
        if index == 3 { Err(()) } else { Ok(Item(&dropped)) }
    });
    assert!(result.is_err());
    assert_eq!(dropped.get(), 3);

    let dropped = Cell::new(0);
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let _ = try_build(5, |index| {
            // Deliberate panic injection in a test, not production control flow.
            assert_ne!(index, 3);
            Ok::<_, ()>(Item(&dropped))
        });
    }));
    assert!(outcome.is_err());
    assert_eq!(dropped.get(), 3);
}
```

The owner tracks each successful push. No destructor is run for an uninitialized element. The unwind test requires an unwinding panic strategy; the assertion is a deliberate fault injection.

## When Raw Storage Is Necessary

Use a guard that owns the allocation and records exactly the initialized prefix or other initialized set. Update that record immediately after successful writes, before any potentially panicking work. On success, transfer ownership exactly once and disarm the guard without introducing another fallible step. On error or unwind, destroy only initialized values and release allocation according to its contract. Prefer safe standard-library construction APIs whenever they fit.

For mutation of existing state, prepare fallible results before modifying the live owner. When that is impossible, maintain a sound intermediate representation (e.g. `Option<T>`) or use an explicit transaction. Consider a destructor itself panicking during cleanup; leaked resources on exceptional paths may be preferable to double drops or invalid memory access. Do not promise cleanup on abort or when a guard is forgotten.

## Review Checklist

- Can any operation panic, invoke external code, return early, or suspend?
- What happens if it fails after each successful initialization or mutation?
- Can a safe caller forget a guard, or obtain access to state during reentrancy?
- Is the allocation released by the correct owner and are initialized values dropped at most once?
- Can the callback or destructor itself panic? Does the type remain sound after catching an unwind?

Test each relevant failure boundary, including zero items, first/last failure, success and repeated calls. Miri complements but does not replace the proof.

## See Also

- [unsafe-untrusted-safe-code](./unsafe-untrusted-safe-code.md)
- [unsafe-maybeuninit](./unsafe-maybeuninit.md)
- [mem-drop-guard](./mem-drop-guard.md)
- [async-cancel-safety](./async-cancel-safety.md)
- [Rustonomicon: Exception Safety](https://doc.rust-lang.org/nomicon/exception-safety.html)
