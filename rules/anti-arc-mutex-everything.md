# anti-arc-mutex-everything

> Don't default to `Arc<Mutex<T>>` for every shared state problem

## Why It Matters

`Arc<Mutex<T>>` is the default answer many Rust newcomers reach for when they need shared state. But it comes with costs: contention (only one task can hold the lock), cognitive overhead (lock scoping, poisoning), and error-proneness (deadlocks, held-across-await). For many problems, simpler or more efficient alternatives exist.

## Bad

```rust
use std::sync::{Arc, Mutex};

// Everything is Arc<Mutex<T>>
struct Server {
    config: Arc<Mutex<Config>>,
    metrics: Arc<Mutex<Metrics>>,
    clients: Arc<Mutex<HashMap<Id, Client>>>,
}

async fn handle_request(server: &Server) {
    let config = server.config.lock().unwrap();
    let mut metrics = server.metrics.lock().unwrap();
    let clients = server.clients.lock().unwrap();
    // ... complex lock interactions ...
}
```

## Good

### Alternative 1: Channels (Message Passing)

```rust
use tokio::sync::mpsc;

// Actor-like: single task owns the state, others send messages
enum Command {
    UpdateConfig(Config),
    RecordMetric(String, f64),
    GetMetrics(oneshot::Sender<Metrics>),
}

struct Actor {
    config: Config,
    metrics: Metrics,
    rx: mpsc::Receiver<Command>,
}

impl Actor {
    async fn run(&mut self) {
        while let Some(cmd) = self.rx.recv().await {
            match cmd {
                Command::UpdateConfig(c) => self.config = c,
                Command::RecordMetric(k, v) => self.metrics.record(k, v),
                Command::GetMetrics(tx) => { let _ = tx.send(self.metrics.clone()); }
            }
        }
    }
}
```

### Alternative 2: Lock-Free Atomics

```rust
use std::sync::atomic::{AtomicU64, Ordering};

// Simple counters need no lock
struct Metrics {
    requests: AtomicU64,
    errors: AtomicU64,
    latency_sum: AtomicU64,
}

impl Metrics {
    fn record_request(&self, latency_us: u64) {
        self.requests.fetch_add(1, Ordering::Relaxed);
        self.latency_sum.fetch_add(latency_us, Ordering::Relaxed);
    }

    fn avg_latency(&self) -> f64 {
        let reqs = self.requests.load(Ordering::Relaxed);
        if reqs == 0 { return 0.0; }
        self.latency_sum.load(Ordering::Relaxed) as f64 / reqs as f64
    }
}
```

### Alternative 3: Per-Task State (No Sharing)

```rust
use std::collections::HashMap;

// Instead of Arc<Mutex<HashMap>>, give each task its own copy
async fn process_connections(config: Config) {
    let mut local_state = HashMap::new();
    // Each connection handler has independent state
    // No locks needed — no sharing!
}
```

### Alternative 4: Actor Model with `tokio::spawn`

```rust
use tokio::sync::mpsc;

// Single-owner actor: state is NOT shared, it's owned by one task
struct DatabaseActor {
    conn: sqlx::PgPool,
    cache: HashMap<String, Data>,
}

impl DatabaseActor {
    async fn run(&mut self, mut rx: mpsc::Receiver<Query>) {
        while let Some(query) = rx.recv().await {
            match query {
                Query::Get(key, tx) => {
                    let data = self.cache.get(&key).cloned()
                        .or_else(|| self.fetch_from_db(&key));
                    let _ = tx.send(data);
                }
            }
        }
    }
}

// Other tasks own only a Sender — no locks
let (tx, rx) = mpsc::channel(128);
tokio::spawn(DatabaseActor::new(pool).run(rx));
```

## Decision Guide

| Problem | Recommended Approach |
|---------|---------------------|
| Simple counter / flag | `AtomicU64`, `AtomicBool` |
| One writer, many readers | `RwLock<T>` (if reads dominate) |
| Task owns state, others query | `mpsc` / `oneshot` channels |
| Rarely accessed shared config | `Arc<Mutex<T>>` (with minimal scope) |
| Complex state machine | Actor model via channels |
| Per-connection state | Owned per-task (no sharing) |

## When Arc<Mutex<T>> IS Appropriate

```rust
use std::sync::{Arc, Mutex};

// OK: Rarely written, infrequently accessed shared resource
let cache: Arc<Mutex<HashMap<String, CachedData>>> = Arc::new(Mutex::new(HashMap::new()));

// OK: Mutex scope is minimal — no held across .await
fn get_cached(cache: &Mutex<HashMap<String, CachedData>>, key: &str) -> Option<CachedData> {
    let map = cache.lock().unwrap();
    map.get(key).cloned()
}  // Lock released immediately
```

## Detection

```toml
[lints.clippy]
mutex_atomic = "warn"  # Suggests atomics over Mutex<bool|u32|etc.>
```

## See Also

- [async-runtime-metrics](./async-runtime-metrics.md) — Monitor blocking pool pressure with RuntimeMetrics
- [conc-atomic-ordering](./conc-atomic-ordering.md) — Use atomics instead of locks for simple counters
- [async-mpsc-queue](./async-mpsc-queue.md) — Channel-based message passing over shared state

## References

- [Rust Design Patterns: Message passing](https://rust-unofficial.github.io/patterns/patterns/behavioural/actor.html)
- [C++ and Beyond 2012: Channels vs Mutex (Herb Sutter)](https://channel9.msdn.com/Shows/GoingDeep/C-and-Beyond-2012-Herb-Sutter-Concurrency-and-Parallelism)
- [Tokio: Shared state](https://tokio.rs/tokio/tutorial/shared-state)
