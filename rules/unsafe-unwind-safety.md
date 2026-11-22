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

    let result = try_build(5, |_| Ok::<_, ()>(Item(&dropped)));
    assert!(result.is_ok());
    assert_eq!(dropped.get(), 3);
    drop(result);
    assert_eq!(dropped.get(), 8);
}
```

The owner tracks each successful push. No destructor is run for an uninitialized element. The direct initialization example below also checks unwinding with deliberate test fault injection under an unwinding panic strategy.

## When Raw Storage Is Necessary

Use a guard that owns the allocation and records exactly the initialized prefix or other initialized set. Update that record immediately after successful writes, before any potentially panicking work. On success, transfer ownership exactly once and disarm the guard without introducing another fallible step. On error or unwind, destroy only initialized values and release allocation according to its contract. Prefer safe standard-library construction APIs whenever they fit.

For mutation of existing state, prepare fallible results before modifying the live owner. When that is impossible, maintain a sound intermediate representation (e.g. `Option<T>`) or use an explicit transaction. Consider a destructor itself panicking during cleanup; leaked resources on exceptional paths may be preferable to double drops or invalid memory access. Do not promise cleanup on abort or when a guard is forgotten.

## Direct Initialization With an Owning Prefix Guard

When an allocation must be initialized in place, use a private owner with
an initialization record. The following illustrates the mechanics for a
boxed slice. Prefer the safe vector construction above for normal Rust
values; do not reimplement it merely to demonstrate unsafe code.

<!-- rust-check: run -->
```rust
use std::cell::Cell;
use std::mem::MaybeUninit;
use std::panic::{catch_unwind, AssertUnwindSafe};

struct Prefix<T> {
    storage: Box<[MaybeUninit<T>]>,
    initialized: usize,
}

impl<T> Drop for Prefix<T> {
    fn drop(&mut self) {
        for slot in &mut self.storage[..self.initialized] {
            // SAFETY: the guard owns exactly this initialized prefix.
            unsafe { slot.assume_init_drop() };
        }
    }
}

fn try_build_direct<T, E>(
    count: usize,
    mut make: impl FnMut(usize) -> Result<T, E>,
) -> Result<Box<[T]>, E> {
    let mut guard = Prefix {
        storage: Box::<[T]>::new_uninit_slice(count),
        initialized: 0,
    };

    for index in 0..count {
        let value = make(index)?;
        guard.storage[index].write(value);
        // index < count proves index + 1 fits; no fallible work intervenes.
        guard.initialized = index + 1;
    }

    let storage = std::mem::take(&mut guard.storage);
    guard.initialized = 0;
    // SAFETY: every slot was written exactly once; the guard no longer owns
    // any initialized values. This transfer adds no intervening user code.
    Ok(unsafe { storage.assume_init() })
}

struct Item<'a>(&'a Cell<usize>);

impl Drop for Item<'_> {
    fn drop(&mut self) {
        self.0.set(self.0.get() + 1);
    }
}

fn main() {
    for failure in 0..5 {
        let dropped = Cell::new(0);
        let result = try_build_direct(5, |index| {
            if index == failure { Err(()) } else { Ok(Item(&dropped)) }
        });
        assert!(result.is_err());
        assert_eq!(dropped.get(), failure);

        let dropped = Cell::new(0);
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            let _ = try_build_direct(5, |index| {
                assert_ne!(index, failure); // deliberate test fault
                Ok::<_, ()>(Item(&dropped))
            });
        }));
        assert!(outcome.is_err());
        assert_eq!(dropped.get(), failure);
    }

    for count in [0, 5] {
        let dropped = Cell::new(0);
        let result = try_build_direct(count, |_| Ok::<_, ()>(Item(&dropped)));
        assert!(result.is_ok());
        assert_eq!(dropped.get(), 0);
        drop(result);
        assert_eq!(dropped.get(), count);
    }
}
```

The private guard's record is updated after each write. If an element's
destructor itself panics, the remaining elements can leak, but the guard
does not re-expose the allocation or double-drop already destroyed values.
A panic during unwinding may abort. Do not promise universal cleanup or
make memory safety depend on the destructor returning.

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
