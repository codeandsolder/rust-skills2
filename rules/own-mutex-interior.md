# own-mutex-interior

> Use the right `Mutex<T>` for the execution model: `std`/`parking_lot` for synchronous code, `tokio::sync::Mutex` for async code

## Why It Matters

When you need shared mutable state across threads, `Mutex<T>` provides safe interior mutability with synchronization. Unlike `RefCell`, `Mutex` is `Send + Sync` and ensures only one task or thread mutates the data at a time.

The lock choice depends on where the data is used:

- `std::sync::Mutex` or `parking_lot::Mutex` for synchronous code
- `tokio::sync::Mutex` for async code that must acquire the lock from async tasks

## Bad

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

## Good

```rust
use std::sync::{Arc, Mutex};

let shared = Arc::new(Mutex::new(vec![]));

let handles: Vec<_> = (0..10).map(|i| {
    let shared = shared.clone();
    std::thread::spawn(move || {
        let mut data = shared.lock().unwrap();
        data.push(i);
    })
}).collect();

for handle in handles {
    handle.join().unwrap();
}

println!("{:?}", shared.lock().unwrap()); // All values present
```

## Mutex Poisoning

If a thread panics while holding a lock, the mutex becomes "poisoned":

```rust
use std::sync::{Arc, Mutex};

let mutex = Arc::new(Mutex::new(0));

// Handle poisoning gracefully
match mutex.lock() {
    Ok(guard) => println!("Value: {}", *guard),
    Err(poisoned) => {
        // Recover the data anyway
        let guard = poisoned.into_inner();
        println!("Recovered value: {}", *guard);
    }
}

// Or ignore poisoning (use with caution)
let guard = mutex.lock().unwrap_or_else(|e| e.into_inner());
```

## Async code needs tokio::sync::Mutex

```rust
use std::sync::Arc;
use tokio::sync::Mutex;

struct State {
    counter: usize,
}

async fn increment(state: Arc<Mutex<State>>) {
    let mut guard = state.lock().await;
    guard.counter += 1;
}
```

Do not default to `std::sync::Mutex` or `parking_lot::Mutex` in async code unless the critical section is tiny, fully synchronous, and you are sure no `.await` can occur while the guard is live.

Note: `std::sync::Mutex` has improved significantly, but the general rule remains — prefer `tokio::sync::Mutex` when the guard will span `.await` boundaries.

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
- Smaller size (1 byte vs 40+ bytes)
- Better performance under contention
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
- For short, synchronous critical sections that do not cross `.await`, `std::sync::Mutex` is faster even in async code.

## When to Use What

| Type | Threading | Overhead | Use Case |
|------|-----------|----------|----------|
| `RefCell<T>` | Single | Minimal | Interior mutability, same thread |
| `std::sync::Mutex<T>` | Multi | Locking | Shared mutable state in synchronous code |
| `tokio::sync::Mutex<T>` | Async multi-task | Awaitable lock | Shared mutable state in async code |
| `RwLock<T>` | Multi | Locking | Many readers, few writers |
| `parking_lot::Mutex<T>` | Multi | Less (narrowed gap) | Synchronous code with contention-sensitive locks |

## See Also

- [own-rwlock-readers](./own-rwlock-readers.md) - When reads dominate writes
- [own-refcell-interior](./own-refcell-interior.md) - Single-threaded alternative
- [async-no-lock-await](./async-no-lock-await.md) - Avoiding locks across await points
