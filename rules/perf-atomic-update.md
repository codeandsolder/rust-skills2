# perf-atomic-update

> Use `Atomic*::update` and `try_update` for cleaner compare-and-update loops

**Rule**: `perf-atomic-update`

## Why It Matters

Compare-and-exchange loops are the building block of many lock-free atomic updates. The manual pattern is easy to get wrong or make unnecessarily verbose. Rust 1.95 added `update` and `try_update` across the atomic types so common compare-and-update loops can be expressed directly.

These methods do **not** change the memory-model requirements: you still choose the success and failure orderings, and the closure may run more than once under contention. Keep the closure free of externally visible side effects.

## Bad

```rust
use std::sync::atomic::{AtomicU32, Ordering};

fn increment_counter(counter: &AtomicU32) {
    let mut current = counter.load(Ordering::Acquire);
    loop {
        let new = current + 1;
        match counter.compare_exchange_weak(
            current,
            new,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => break,
            Err(observed) => current = observed,
        }
    }
}
```

Manual CAS loops are sometimes necessary, but they should update the expected value from the failed comparison and use orderings appropriate to the synchronization invariant.

## Good

```rust
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

fn increment_counter(counter: &AtomicU32) {
    counter.update(
        Ordering::AcqRel,
        Ordering::Acquire,
        |current| current + 1,
    );
}

// `update` returns the value that was stored before the successful update.
fn add_saturating(stats: &AtomicU64, delta: u64) -> u64 {
    stats.update(
        Ordering::AcqRel,
        Ordering::Acquire,
        |current| current.saturating_add(delta),
    )
}
```

`update(set_order, fetch_order, f)` repeatedly applies `f` as needed and stores its returned value. Its return value is the **previous** atomic value, matching the `fetch_*` family.

## `try_update`: Conditional Update

`try_update` uses an `Option`, not an application-defined `Result`: return `Some(new_value)` to attempt the update or `None` to abort. The method returns `Ok(previous_value)` on a successful store and `Err(previous_value)` when the closure returns `None`.

```rust
use std::sync::atomic::{AtomicU64, Ordering};

fn try_decrement(counter: &AtomicU64) -> Result<u64, u64> {
    counter.try_update(
        Ordering::AcqRel,
        Ordering::Acquire,
        |current| current.checked_sub(1),
    )
}
```

If callers need a domain-specific error, translate the returned previous value at the API boundary rather than returning `Err(custom_error)` from the atomic closure.

## Supported Types

The `update` / `try_update` family is available on the corresponding stable atomic types when the target supports that atomic width, including integer atomics, `AtomicBool`, and `AtomicPtr<T>`. Do not assume every width exists on every target; use the `target_has_atomic` configuration when portability across constrained targets matters.

`fetch_update`, stabilized earlier, has similar conditional-update semantics. In Rust 1.95 the `try_update` name was added for consistency alongside the non-fallible `update` API.

## Performance and Correctness

`update` is an abstraction over the same kind of compare-and-exchange retry loop you would otherwise write manually. Its main benefit is clarity and reducing loop bookkeeping, not a promise of faster machine code.

The closure may be evaluated multiple times if another thread changes the atomic between attempts. Therefore this is appropriate:

```rust
counter.update(Ordering::Relaxed, Ordering::Relaxed, |x| x + 1);
```

but a closure that sends messages, mutates unrelated state, performs I/O, or otherwise assumes exactly-once execution is usually wrong.

## Ordering Guide

| Success ordering | Failure ordering | Typical intent |
|------------------|------------------|----------------|
| `Relaxed` | `Relaxed` | Atomicity only, such as independent metrics |
| `Release` | `Relaxed` | Publish prior writes |
| `Acquire` | `Acquire` | Acquire data published by another thread |
| `AcqRel` | `Acquire` | Read-modify-write synchronization |
| `SeqCst` | `SeqCst` | Participate in a global sequentially consistent order |

Choose orderings from the synchronization invariant; do not mechanically upgrade every operation to `AcqRel` or `SeqCst`.

## See Also

- [own-mutex-interior](./own-mutex-interior.md) - Mutex for interior mutability
- [own-arc-shared](./own-arc-shared.md) - Arc for shared ownership
- [anti-premature-optimize](./anti-premature-optimize.md) - Profile before optimizing
