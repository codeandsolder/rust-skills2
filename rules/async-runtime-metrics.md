# async-runtime-metrics

> Use `RuntimeMetrics` for task health, blocking thread pressure, and starvation detection

**Rule**: `async-runtime-metrics`

## Why It Matters

Production async systems fail silently more often than they crash. Tasks can be starved, the blocking pool can saturate, and cross-thread scheduling can degrade—all without any `Err` return. `RuntimeMetrics` exposes these internal states, turning invisible degradation into observable signals. Without metrics, you are flying blind.

## Usage Prerequisites

RuntimeMetrics requires the `tokio_unstable` cfg flag:

```toml
# .cargo/config.toml
[build]
rustflags = ["--cfg", "tokio_unstable"]
```

```toml
# Cargo.toml
[dependencies]
tokio = { version = "1", features = ["rt", "rt-multi-thread"] }
```

## Accessing Metrics

```rust
use tokio::runtime::Runtime;

let runtime = Runtime::new()?;
let metrics = runtime.metrics();

// Monitor from another task
runtime.spawn(async {
    let mut interval = tokio::time::interval(Duration::from_secs(10));
    loop {
        interval.tick().await;
        report_metrics(&metrics);
    }
});
```

## Key Metrics

### Task Health

```rust
use tokio::runtime::RuntimeMetrics;

fn report_task_health(metrics: &RuntimeMetrics) {
    // Active tasks currently being polled
    let active = metrics.num_alive_tasks();
    
    // Remote schedule count: tasks spawned from other worker threads
    // High values indicate cross-thread scheduling overhead
    let remote = metrics.remote_schedule_count();
    
    // Total poll count across all workers: can detect task starvation
    let num_workers = metrics.num_workers();
    let total_polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
    
    info!("Tasks: active={}, remote_scheduled={}, total_polls={}",
        active, remote, total_polls);
}
```

### Blocking Pool Pressure

```rust
fn check_blocking_pool(metrics: &RuntimeMetrics) -> HealthStatus {
    let queue_depth = metrics.blocking_queue_depth();
    let num_threads = metrics.num_blocking_threads();
    
    match queue_depth {
        0 => HealthStatus::Healthy,
        1..=10 => HealthStatus::Warning,
        11..=50 => HealthStatus::Critical,
        _ => HealthStatus::Overloaded,
    }
    
    // Metrics also expose max values
    // metrics.max_num_blocking_threads() - peak blocking threads
    // (available when tokio_unstable is enabled)
}
```

### Starvation Detection

```rust
async fn detect_starvation(metrics: &RuntimeMetrics) {
    let num_workers = metrics.num_workers();
    let mut prev_polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
    
    loop {
        tokio::time::sleep(Duration::from_secs(1)).await;
        let current_polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
        let delta = current_polls - prev_polls;
        prev_polls = current_polls;
        
        // If poll count doesn't increase, tasks are starving
        if delta < 10 && metrics.num_alive_tasks() > 0 {
            warn!("Potential task starvation: only {} polls in 1s", delta);
        }
    }
}
```

## Bad

```rust
use tokio::runtime::Runtime;

fn main() {
    let rt = Runtime::new().unwrap();
    rt.block_on(async {
        loop {
            // Heavy CPU work blocks async tasks
            std::thread::sleep(Duration::from_millis(100)); // Blocks!
        }
    });
}
// Not observable: no metrics, no logging, no alerting
```

## Good

```rust
use tokio::runtime::{Runtime, RuntimeMetrics};

fn main() {
    let rt = Builder::new_multi_thread()
        .worker_threads(4)
        .build()
        .unwrap();
    
    let metrics = rt.metrics();
    
    // Spawn a health monitor
    rt.spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            
            let blocking_depth = metrics.blocking_queue_depth();
            if blocking_depth > 5 {
                // Observable: we know blocking is happening
                warn!("Blocking pool pressure: {} queued", blocking_depth);
            }
        }
    });
    
    rt.block_on(async { /* application */ });
}
```

## tokio-console Integration

For richer diagnostics, integrate with [`tokio-console`](https://github.com/tokio-rs/console):

```toml
# Cargo.toml
[dependencies]
tokio = { version = "1", features = ["rt", "rt-multi-thread"] }
console-subscriber = "0.4"
```

```rust
// Initialize console subscriber early
#[tokio::main]
async fn main() {
    console_subscriber::init();
    // Run your app...
}
```

Then run `tokio-console` in a terminal:
```bash
cargo install tokio-console
tokio-console
```

This provides real-time visualization of tasks, resources, and async operations.

## Metrics Loop Pattern

```rust
use tokio::runtime::RuntimeMetrics;

struct HealthReport {
    active_tasks: usize,
    blocking_queue_depth: usize,
    total_poll_count: u64,
    remote_schedule_count: u64,
}

async fn metrics_collector(metrics: RuntimeMetrics) -> mpsc::Receiver<HealthReport> {
    let (tx, rx) = mpsc::channel::<HealthReport>(100);
    
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(10));
        loop {
            interval.tick().await;
            let num_workers = metrics.num_workers();
            let total_polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
            let report = HealthReport {
                active_tasks: metrics.num_alive_tasks(),
                blocking_queue_depth: metrics.blocking_queue_depth(),
                total_poll_count: total_polls,
                remote_schedule_count: metrics.remote_schedule_count(),
            };
            if tx.send(report).await.is_err() {
                break; // Receiver dropped
            }
        }
    });
    
    rx
}
```

## See Also

- [async-blocking-detection](./async-blocking-detection.md) — Detect blocking in async code
- [async-tokio-runtime](./async-tokio-runtime.md) — Runtime configuration
- [async-joinset-structured](./async-joinset-structured.md) — Structured concurrency with JoinSet

## References

- [RuntimeMetrics docs](https://docs.rs/tokio/latest/tokio/runtime/struct.RuntimeMetrics.html)
- [tokio-console](https://github.com/tokio-rs/console)
- [async-tokio-runtime](./async-tokio-runtime.md) - Runtime configuration
- [async-blocking-detection](./async-blocking-detection.md) - Detecting blocking in async
