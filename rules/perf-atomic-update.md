# perf-atomic-update

> Use `Atomic*::update` and `try_update` for cleaner CAS loops

**Rule**: `perf-atomic-update`

## Why It Matters

Compare-and-swap (CAS) loops are the building block of lock-free atomic operations. The manual pattern of `load` + `compare_exchange` in a loop is error-prone: subtle bugs can introduce infinite loops, ABA problems, or missed updates. `Atomic*::update` (Rust 1.95+) and `Atomic*::try_update` wrap the CAS loop into a single function call, eliminating boilerplate and common mistakes.

## Bad

```rust
use std::sync::atomic::{AtomicU32, Ordering};

// Manual CAS loop — easy to get wrong
fn increment_counter(counter: &AtomicU32) {
    loop {
        let current = counter.load(Ordering::Acquire);
        let new = current + 1;
        if counter.compare_exchange_weak(
            current,
            new,
            Ordering::Release,
            Ordering::Acquire,
        ).is_ok() {
            break;
        }
        // Spurious failure: retry
        // Forgot to reload? ABA? Wrong ordering?
    }
}

// Manual CAS with non-trivial update — duplicated logic
fn update_stats(stats: &AtomicU64, delta: u64) {
    loop {
        let current = stats.load(Ordering::Acquire);
        let new = current.saturating_add(delta);
        if stats.compare_exchange_weak(
            current,
            new,
            Ordering::Release,
            Ordering::Acquire,
        ).is_ok() {
            break;
        }
    }
}
```

## Good

```rust
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

// update wraps the CAS loop internally
fn increment_counter(counter: &AtomicU32) {
    counter.update(|current| current + 1, Ordering::AcqRel, Ordering::Acquire);
    // No loop, no manual load/compare_exchange
}

// update returns the value passed to and returned from the closure
fn update_stats(stats: &AtomicU64, delta: u64) -> u64 {
    stats.update(
        |current| current.saturating_add(delta),
        Ordering::AcqRel,
        Ordering::Acquire,
    )
}
```

## try_update (Fallible CAS)

`try_update` allows the closure to return `Err` to abort the CAS loop:

```rust
use std::sync::atomic::{AtomicU64, Ordering};

// Try to decrement, but don't go below zero
fn try_decrement(counter: &AtomicU64) -> Result<u64, ()> {
    counter.try_update(
        |current| {
            if current == 0 {
                Err(())  // Abort CAS loop
            } else {
                Ok(current - 1)
            }
        },
        Ordering::AcqRel,
        Ordering::Acquire,
    )
}
```

## Supported Atomic Types

| Type | Methods | Since |
|------|---------|-------|
| `AtomicBool` | `update`, `try_update` | 1.95 |
| `AtomicI8` | `update`, `try_update` | 1.95 |
| `AtomicU8` | `update`, `try_update` | 1.95 |
| `AtomicI16` | `update`, `try_update` | 1.95 |
| `AtomicU16` | `update`, `try_update` | 1.95 |
| `AtomicI32` | `update`, `try_update` | 1.95 |
| `AtomicU32` | `update`, `try_update` | 1.95 |
| `AtomicI64` | `update`, `try_update` | 1.95 |
| `AtomicU64` | `update`, `try_update` | 1.95 |
| `AtomicI128` | `update`, `try_update` | 1.95 |
| `AtomicU128` | `update`, `try_update` | 1.95 |
| `AtomicPtr<T>` | — | — |
| `AtomicUsize` | `fetch_update` | 1.45 (legacy) |

## Legacy: fetch_update (Rust 1.45+)

Before `update`/`try_update`, the similar `AtomicUsize::fetch_update` existed but required `Result` return type:

```rust
use std::sync::atomic::{AtomicUsize, Ordering};

// Legacy fetch_update — predates update/try_update
let result = atomic.fetch_update(
    Ordering::Release,
    Ordering::Acquire,
    |current| {
        Some(current + 1)  // None to abort
    },
);
```

With `update` (1.95+), the simpler non-fallible API is preferred. `fetch_update` remains for `AtomicUsize` specifically.

## Performance

| Pattern | Instructions | Spurious Retries | Clarity |
|---------|-------------|------------------|---------|
| Manual CAS loop | Same as update | Same | Low — easy to misorder |
| `atomic.update(f)` | Same as manual | Same | High — single function call |
| `atomic.try_update(f)` | Same as fn_returning_Result | Same | High — abort on error |

Both `update` and manual CAS loops compile to the same machine code. The advantage is entirely in readability and correctness.

## Ordering Guide

| Success Ordering | Failure Ordering | Use Case |
|-----------------|------------------|----------|
| `Relaxed` | `Relaxed` | No synchronization needed (metrics) |
| `Release` | `Relaxed` | Writer, no immediate reader |
| `AcqRel` | `Acquire` | Reader-writer synchronization |
| `SeqCst` | `SeqCst` | Strongest guarantees (rarely needed) |

## See Also

- [own-mutex-interior](./own-mutex-interior.md) - Mutex for interior mutability
- [own-arc-shared](./own-arc-shared.md) - Arc for shared ownership
- [anti-premature-optimize](./anti-premature-optimize.md) - Profile before optimizing
