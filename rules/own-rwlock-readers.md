# own-rwlock-readers

> Choose `RwLock<T>` when concurrent readers materially help the measured workload, not from a fixed read/write ratio

## Why It Matters

A `Mutex<T>` permits one lock holder at a time. An `RwLock<T>` permits multiple readers or one exclusive writer. That can improve throughput when read-side concurrency is valuable, but the extra state and scheduling policy are not free.

There is no portable rule such as “use `RwLock` below 20% writes.” The result depends on contention, critical-section duration, core count, implementation, scheduler policy, cache behavior, and latency requirements. Start from semantics, then measure under representative contention.

## Mutex: Simpler Exclusive Access

<!-- rust-check: compile -->
```rust
use std::sync::Mutex;

#[derive(Default)]
struct Config {
    enabled: bool,
}

fn is_enabled(config: &Mutex<Config>) -> bool {
    config.lock().unwrap().enabled
}

fn set_enabled(config: &Mutex<Config>, enabled: bool) {
    config.lock().unwrap().enabled = enabled;
}
```

This is often a good baseline for short critical sections. A mutex is not “wrong” merely because most operations happen to read.

## RwLock: Concurrent Read Guards

<!-- rust-check: compile -->
```rust
use std::sync::RwLock;

#[derive(Default)]
struct Config {
    enabled: bool,
}

fn is_enabled(config: &RwLock<Config>) -> bool {
    config.read().unwrap().enabled
}

fn set_enabled(config: &RwLock<Config>, enabled: bool) {
    config.write().unwrap().enabled = enabled;
}
```

Several threads may hold `read()` guards at once. That means the lock permits concurrent readers; it does **not** guarantee that one hundred readers literally execute in parallel or that this beats a mutex in a particular workload.

## Pick the Lock for the Execution Context

For synchronous code, `std::sync::{Mutex, RwLock}` and alternatives such as `parking_lot` are appropriate choices. For async code, use an async-aware lock when acquiring or holding the lock must participate in async scheduling.

```rust
use std::sync::Arc;
use tokio::sync::RwLock;

struct Config {
    enabled: bool,
}

async fn is_enabled(config: Arc<RwLock<Config>>) -> bool {
    config.read().await.enabled
}

async fn set_enabled(config: Arc<RwLock<Config>>, enabled: bool) {
    config.write().await.enabled = enabled;
}
```

Do not turn every lock touched by async code into a Tokio lock mechanically. A synchronous mutex/RwLock can still be appropriate for a very short data-only critical section that never crosses `.await`. Conversely, never block an executor worker waiting on a heavily contended synchronous lock merely because the guard is eventually dropped before `.await`.

## Fairness Is Implementation-Specific

Do not promise a portable reader- or writer-preference policy for `std::sync::RwLock`; the standard library delegates priority policy to the underlying platform and does not guarantee one policy across targets.

`parking_lot::RwLock` documents a task-fair/eventual-fair policy. That is a property of that implementation, not of the `RwLock` abstraction in general.

```rust
use parking_lot::RwLock;

let lock = RwLock::new(vec![1, 2, 3]);
let len = lock.read().len();
assert_eq!(len, 3);
lock.write().push(4);
```

If starvation or tail latency matters, evaluate the chosen implementation under the real scheduling pattern instead of inferring it from the type name.

## Upgrade/Downgrade and Check-Then-Write Patterns

A common trap is assuming that dropping a read guard and later taking a write guard preserves what was observed. It does not: another writer may change the value in between.

`parking_lot` offers an upgradeable read guard for cases that need an atomic read-to-write transition:

```rust
use parking_lot::{RwLock, RwLockUpgradableReadGuard};
use std::collections::HashMap;

let lock = RwLock::new(HashMap::<String, String>::new());
let guard = lock.upgradable_read();
if !guard.contains_key("key") {
    let mut write = RwLockUpgradableReadGuard::upgrade(guard);
    write.insert("key".to_owned(), "default".to_owned());
}
```

Use implementation-specific transition APIs when their atomicity is part of the algorithm; otherwise keep the locking protocol simple.

## Cached Computation: Avoid Assuming One Computation

This common double-checked shape can compute the same value concurrently if several readers miss before any writer stores the result:

```rust
use std::sync::RwLock;

struct Cache {
    value: RwLock<Option<String>>,
}

impl Cache {
    fn get_or_compute(&self) -> String {
        if let Some(value) = self.value.read().unwrap().clone() {
            return value;
        }

        let computed = "computed".to_owned();
        let mut write = self.value.write().unwrap();
        write.get_or_insert_with(|| computed).clone()
    }
}
```

Duplicate computation may be acceptable. If exactly-once initialization is required, use a primitive designed for that invariant such as `OnceLock`/`LazyLock` or an explicit state machine rather than assuming `RwLock` makes the check-and-compute sequence atomic.

## Decision Guide

Prefer the simplest primitive that expresses the invariant, then benchmark if contention matters:

| Situation | Start by considering |
|---|---|
| Short exclusive critical sections | `Mutex` |
| Multiple simultaneous readers are measurably valuable | `RwLock` |
| One-time initialization | `OnceLock` / `LazyLock` |
| Async acquisition/guard semantics are required | Tokio async lock |
| Read-mostly snapshots with rare replacement | immutable snapshot / copy-on-write designs may avoid shared lock contention |

Read/write percentage alone is not enough information.

## See Also

- [own-mutex-interior](./own-mutex-interior.md) - exclusive interior mutability
- [async-no-lock-await](./async-no-lock-await.md) - lock choices in async code
