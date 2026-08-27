# anti-arc-mutex-everything

> Do not default to `Arc<Mutex<T>>` when ownership, channels, atomics, or another synchronization primitive better matches the state

## Why It Matters

`Arc<Mutex<T>>` is a useful way to share mutable state, not a universal default. A mutex serializes access to the protected value, and every caller must reason about lock scope and lock ordering. In async code, the choice between a synchronous mutex and an async mutex also matters.

Start from the ownership model and required operations:

- keep state owned by one task when possible;
- use channels when other tasks should request operations from that owner;
- use atomics for simple independent values when their ordering semantics are understood;
- use a mutex or `RwLock` when shared in-place access is actually the clearest model.

Do not replace a mutex mechanically. A channel can add queueing and lifecycle complexity, an `RwLock` is not automatically faster, and several atomics do not provide a consistent multi-field snapshot by themselves.

## Bad: Unnecessary Shared Mutable State

```rust
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Server {
    counters: Arc<Mutex<HashMap<String, u64>>>,
}

fn record(server: &Server, key: &str) {
    let mut counters = server.counters.lock().unwrap();
    *counters.entry(key.to_owned()).or_default() += 1;
}

fn main() {
    let server = Server::default();
    record(&server, "requests");
}
```

This is legal Rust. The problem is treating shared locking as the starting point even when the state could have a simpler owner or representation.

## Good: Single-Owner State with Messages

```rust
use std::collections::HashMap;
use tokio::sync::{mpsc, oneshot};

enum Command {
    Increment(String),
    Read {
        key: String,
        reply: oneshot::Sender<u64>,
    },
}

async fn run_counter(mut rx: mpsc::Receiver<Command>) {
    let mut counts = HashMap::<String, u64>::new();

    while let Some(command) = rx.recv().await {
        match command {
            Command::Increment(key) => {
                *counts.entry(key).or_default() += 1;
            }
            Command::Read { key, reply } => {
                let _ = reply.send(counts.get(&key).copied().unwrap_or(0));
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let (tx, rx) = mpsc::channel(16);
    let worker = tokio::spawn(run_counter(rx));

    tx.send(Command::Increment("requests".into())).await.unwrap();
    let (reply, value) = oneshot::channel();
    tx.send(Command::Read {
        key: "requests".into(),
        reply,
    })
    .await
    .unwrap();

    assert_eq!(value.await.unwrap(), 1);
    drop(tx);
    worker.await.unwrap();
}
```

This design is attractive when operations naturally belong to one task. It is not automatically superior for every shared-state workload: requests are serialized through the owner and the channel introduces backpressure/lifecycle decisions.

## Good: Atomics for an Independent Counter

```rust
use std::sync::atomic::{AtomicU64, Ordering};

struct Metrics {
    requests: AtomicU64,
}

impl Metrics {
    fn record_request(&self) {
        self.requests.fetch_add(1, Ordering::Relaxed);
    }

    fn requests(&self) -> u64 {
        self.requests.load(Ordering::Relaxed)
    }
}

fn main() {
    let metrics = Metrics {
        requests: AtomicU64::new(0),
    };
    metrics.record_request();
    assert_eq!(metrics.requests(), 1);
}
```

`Relaxed` is sufficient here only because the counter is independent and is not being used to publish or synchronize access to other memory. Choose atomic orderings from the synchronization requirement, not from a blanket rule.

## Good: Own Per-Task State When Sharing Is Unnecessary

```rust
use std::collections::HashMap;

async fn handle_connection() -> usize {
    let mut local = HashMap::new();
    local.insert("requests", 1_u64);
    local.len()
}

#[tokio::main]
async fn main() {
    assert_eq!(handle_connection().await, 1);
}
```

If state has only one logical owner, keeping it local removes synchronization entirely.

## `std::sync::Mutex` Versus `tokio::sync::Mutex`

A synchronous mutex is not forbidden in async code. Tokio explicitly recommends an ordinary blocking mutex for data-only critical sections when the lock is held briefly and never across an `.await`. An async mutex is useful when the guard really must survive across `.await`, but it is more expensive and should not be selected merely because the surrounding function is async.

```rust
use std::collections::HashMap;
use std::sync::Mutex;

fn cached_value(
    cache: &Mutex<HashMap<String, String>>,
    key: &str,
) -> Option<String> {
    let cache = cache.lock().unwrap();
    cache.get(key).cloned()
}

fn main() {
    let cache = Mutex::new(HashMap::from([(
        "answer".to_owned(),
        "42".to_owned(),
    )]));
    assert_eq!(cached_value(&cache, "answer").as_deref(), Some("42"));
}
```

Do not hold a `std::sync::MutexGuard` across an `.await`. If an operation genuinely needs asynchronous work while exclusive access is retained, reconsider the ownership boundary or use an async-aware mutex deliberately.

## `RwLock` Is Not a Mechanical Upgrade

A read-write lock can help when concurrent reads are valuable and writes are sufficiently infrequent/short, but it also has its own coordination overhead and fairness behavior. Measure the workload rather than replacing `Mutex<T>` with `RwLock<T>` solely because reads are common.

## Decision Guide

| Shape of the problem | Usually consider |
|---|---|
| State has one natural owner | owned state, possibly `mpsc`/`oneshot` requests |
| Independent counter/flag | atomic with justified ordering |
| Per-request/per-connection data | owned local state |
| Short synchronous critical section | `std::sync::Mutex` / `parking_lot::Mutex` |
| Guard genuinely crosses `.await` | `tokio::sync::Mutex` or redesign ownership |
| Concurrent reads are important | `RwLock`, after considering contention/fairness |
| Multi-field invariant needs one snapshot | a lock or another coordinated representation |

## Practical Guidance

- Prefer clear ownership over shared ownership when the data model permits it.
- Do not turn several related fields into independent atomics unless the required cross-field consistency is preserved.
- Keep lock scopes small and explicit.
- Do not assume channels, actors, `RwLock`, or lock-free structures are universally faster than a mutex.
- Choose synchronous versus asynchronous mutexes based on whether a guard must cross `.await`, not on whether the caller happens to be async.

## See Also

- [async-mpsc-queue](./async-mpsc-queue.md) — Message passing between tasks
- [conc-atomic-ordering](./conc-atomic-ordering.md) — Atomic ordering semantics
- [async-mutex-choice](./async-mutex-choice.md) — Choosing sync versus async mutexes
