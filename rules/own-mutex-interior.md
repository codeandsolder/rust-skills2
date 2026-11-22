# own-mutex-interior

> Choose locking from critical-section semantics and contention; handle poisoning explicitly and keep synchronous locks out of suspension points

## Why It Matters

When you need shared mutable state across threads, `Mutex<T>` provides safe interior mutability with synchronization. Unlike `RefCell`, a `Mutex<T>` with appropriate `T: Send` supports synchronized shared mutation across threads.

The lock choice depends on where the data is used:

- `std::sync::Mutex` or `parking_lot::Mutex` for synchronous code
- `tokio::sync::Mutex` when waiting must be asynchronous or the operation genuinely requires a guard across suspension (prefer restructuring when possible)

## Bad

<!-- rust-check: compile_fail; reason=RefCell is not Sync and cannot be shared between threads through Arc -->
```rust
use std::cell::RefCell;
use std::sync::Arc;

// RefCell is !Sync - this won't compile
let shared = Arc::new(RefCell::new(vec![]));

// ERROR: RefCell cannot be shared between threads safely
std::thread::spawn({
    let shared = shared.clone();
    move || shared.borrow_mut().push(1)
});
```

## Good: Keep a Short Critical Section and Handle Failure

<!-- rust-check: run -->
```rust
use std::sync::Mutex;

fn increment(value: &Mutex<u32>) -> Result<(), &'static str> {
    let mut guard = value.lock().map_err(|_| "counter poisoned")?;
    *guard = guard.checked_add(1).ok_or("counter overflow")?;
    Ok(())
}

fn main() {
    let value = Mutex::new(0);
    assert_eq!(increment(&value), Ok(()));
    assert_eq!(value.into_inner().ok(), Some(1));
}
```

## Mutex Poisoning

Poisoning of a standard mutex is an advisory indication that an unwind may
have interrupted mutation. It is not a soundness guarantee and panic
detection can be skipped in some contexts. A guard obtained through
`PoisonError::into_inner` still provides locking, but its contents may
violate application invariants.

Choose one explicit policy: propagate the failure, continue if state is
independently known to be usable, or repair while holding the guard and
then clear poison. In this example an expendable cache can be reset.

<!-- rust-check: run -->
```rust
use std::sync::Mutex;

fn repair_cache(cache: &Mutex<Vec<u8>>) -> usize {
    let guard = match cache.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            let mut guard = poisoned.into_inner();
            guard.clear();
            cache.clear_poison();
            guard
        }
    };
    guard.len()
}

fn main() {
    let cache = Mutex::new(vec![1_u8]);
    std::thread::scope(|scope| {
        let result = scope.spawn(|| {
            if let Ok(mut guard) = cache.lock() {
                guard.push(2);
                assert_eq!(guard.len(), 0); // deliberate test fault
            }
        }).join();
        assert!(result.is_err());
    });
    assert!(cache.is_poisoned());
    assert_eq!(repair_cache(&cache), 0);
    assert!(!cache.is_poisoned());
    assert_eq!(cache.into_inner().ok(), Some(vec![]));
}
```

This repair is valid for an expendable byte cache, not for arbitrary
application state. Neither a non-poisoning mutex nor advisory poisoning
removes the need for unwind-safe mutation.

## Async vs Synchronous Locks

```rust
use std::sync::Arc;
use tokio::sync::Mutex;

struct State {
    counter: usize,
}

async fn increment(state: Arc<Mutex<State>>) {
    let mut guard = state.lock().await;
    guard.counter = guard.counter.saturating_add(1);
}
```

Prefer ordinary synchronous locks for short nonblocking critical sections that do not cross an await; if lock acquisition may block a runtime worker substantially, redesign contention or use an async-aware mutex.

If the critical section genuinely spans a suspension, an async mutex supports that operation. The shared policy still rejects holding guards of the diagnosed lock types across await; prefer separating the state update from asynchronous I/O.

## parking_lot::Mutex for synchronous code

For synchronous multi-threaded code, `parking_lot::Mutex` can be a good choice:

```rust
use parking_lot::Mutex;
use std::sync::Arc;

let shared = Arc::new(Mutex::new(vec![]));

// No poisoning, no Result to unwrap
let mut data = shared.lock();
data.push(42);
// Lock automatically released when guard drops
```

Benefits of `parking_lot` in synchronous code:
- No poisoning (returns guard directly)
- Compact implementation on supported targets (size is platform/version dependent)
- Potentially different contention performance
- Fair locking option available

**Note:** The performance gap between `std::sync::Mutex` and `parking_lot::Mutex` has narrowed significantly in recent Rust versions. For most synchronous code, `std::sync::Mutex` is sufficient. Consider `parking_lot` only when profiling shows contention is a bottleneck.

## Recent Additions

### `RwLockWriteGuard::downgrade` (1.92)

Atomically downgrade a write lock to a read lock without releasing the lock:

```rust
use std::sync::RwLock;

let lock = RwLock::new(42);

// 1.92+: write then read without releasing the lock
let write_guard = lock.write().unwrap();
*write_guard += 1;
let read_guard = RwLockWriteGuard::downgrade(write_guard);
println!("Value: {}", *read_guard);
// Lock is still held as read — no race window
```

See [own-rwlock-readers](own-rwlock-readers.md) for more details.

### `From<T>` for `AssertUnwindSafe<T>` (1.96)

```rust
use std::panic::{AssertUnwindSafe, UnwindSafe};
use std::sync::Mutex;

// 1.96+: AssertUnwindSafe<T> now implements From<T>
let mutex = Mutex::new(42);
let safe = AssertUnwindSafe::from(mutex);  // Cleaner than wrapping
```

### Tokio Mutex vs std Mutex — Clarification

- `std::sync::Mutex` locks block the current thread. Never hold these across `.await`.
- `tokio::sync::Mutex` locks are async — they yield the task instead of blocking. Use when the guard spans `.await`.
- For short synchronous critical sections that do not cross `.await`, an ordinary mutex is often cheaper; measure contention and latency.

## When to Use What

| Type | Threading | Overhead | Use Case |
|------|-----------|----------|----------|
| `RefCell<T>` | Single | Minimal | Interior mutability, same thread |
| `std::sync::Mutex<T>` | Multi | Locking | Shared mutable state in synchronous code |
| `tokio::sync::Mutex<T>` | Async multi-task | Awaitable lock | Shared mutable state in async code |
| `RwLock<T>` | Multi | Locking | Many readers, few writers |
| `parking_lot::Mutex<T>` | Multi | Less (narrowed gap) | Synchronous code with contention-sensitive locks |

## See Also

- [unsafe-unwind-safety](./unsafe-unwind-safety.md)
- [err-clippy-unwrap-types](./err-clippy-unwrap-types.md)
- [own-rwlock-readers](./own-rwlock-readers.md) - When reads dominate writes
- [own-refcell-interior](./own-refcell-interior.md) - Single-threaded alternative
- [async-no-lock-await](./async-no-lock-await.md) - Avoiding locks across await points
