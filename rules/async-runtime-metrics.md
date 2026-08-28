# async-runtime-metrics

> Use Tokio runtime metrics as scheduler telemetry, and distinguish stable metrics from `tokio_unstable` instrumentation

## Why It Matters

`tokio::runtime::RuntimeMetrics` exposes observations about a runtime such as worker count, alive-task count, queue depth, and cumulative worker busy time. These signals can help explain scheduler load, but they are not direct diagnoses of “starvation,” “healthy,” or “overloaded.” Interpret them as time series alongside application latency, throughput, errors, and workload information.

The original rule incorrectly treated the entire API as `tokio_unstable`. On current Tokio, several useful metrics are stable, while many detailed scheduler/blocking-pool metrics still require `--cfg tokio_unstable`.

## Good: Stable Runtime Metrics

```rust
use tokio::runtime::Handle;

#[tokio::main]
async fn main() {
    let metrics = Handle::current().metrics();

    let workers = metrics.num_workers();
    let alive = metrics.num_alive_tasks();
    let global_queue = metrics.global_queue_depth();

    println!(
        "workers={workers} alive_tasks={alive} global_queue_depth={global_queue}"
    );
}
```

These methods do not require `tokio_unstable`:

- `num_workers()` — configured runtime worker count;
- `num_alive_tasks()` — current alive task count, with documented weak consistency on the multithreaded runtime;
- `global_queue_depth()` — tasks currently in the runtime's global/injection queue;
- per-worker cumulative metrics such as `worker_total_busy_duration()` on supported targets.

## Good: Measure Deltas, Not Raw Cumulative Counters

Many runtime counters are cumulative. To understand activity over an interval, compare snapshots rather than alerting on the absolute number.

```rust
use std::time::Duration;
use tokio::runtime::Handle;

#[tokio::main]
async fn main() {
    let metrics = Handle::current().metrics();
    let before = metrics.worker_total_busy_duration(0);

    tokio::time::sleep(Duration::from_millis(10)).await;

    let after = metrics.worker_total_busy_duration(0);
    let busy_delta = after.saturating_sub(before);
    println!("worker 0 busy during interval: {busy_delta:?}");
}
```

A busy-time delta can indicate worker load. It does not, by itself, tell you why the worker was busy or whether user-visible latency is acceptable.

## Do Not Invent Universal Health Thresholds

This style of rule is not portable:

```rust
fn classify_queue(depth: usize) -> &'static str {
    match depth {
        0 => "healthy",
        1..=10 => "warning",
        _ => "critical",
    }
}

fn main() {
    assert_eq!(classify_queue(11), "critical");
}
```

A queue depth of 11 might be trivial in one service and catastrophic in another. Thresholds should come from latency objectives, arrival/service rates, capacity tests, and observed baselines.

## `tokio_unstable` Metrics

Detailed metrics including blocking-pool queue depth, blocking thread counts, worker poll counts, worker-local queue depth, remote scheduling counts, and several scheduler counters remain behind `tokio_unstable` in current Tokio.

To use those APIs, Tokio must be compiled with the cfg enabled, for example:

```toml
# .cargo/config.toml
[build]
rustflags = ["--cfg", "tokio_unstable"]
```

Do not present unstable-only methods as ordinary stable-Tokio APIs without stating this requirement.

A representative unstable-metrics helper is:

<!-- rust-check: fixture(tokio-special) -->
```rust
use tokio::runtime::Handle;

fn report_unstable_metrics() {
    let metrics = Handle::current().metrics();
    println!("blocking queue: {}", metrics.blocking_queue_depth());
    println!("blocking threads: {}", metrics.num_blocking_threads());
    println!("worker 0 polls: {}", metrics.worker_poll_count(0));
}
```

This repository compile-checks that exact API family in `checks/fixtures/tokio-special` with the pinned stable Rust toolchain plus `RUSTFLAGS="--cfg tokio_unstable"`. `tokio_unstable` is a Tokio cfg contract, not a Rust nightly language feature, so a dedicated cfg-enabled fixture is more accurate than classifying it as a nightly Rust example.

Treat these metrics as potentially changing across Tokio releases.

## Poll Count Does Not Directly Detect Starvation

A low poll-count delta can mean many things: the runtime may simply be idle, tasks may be waiting on I/O, work may happen on other workers, or a worker may genuinely be blocked. Conversely, a high poll count does not prove healthy latency.

A useful starvation/blocking investigation combines evidence such as:

- application request/operation latency;
- worker busy-time deltas;
- queue-depth trends;
- runtime task/resource instrumentation;
- profiles or traces showing long synchronous sections;
- blocking-pool metrics when `tokio_unstable` is an acceptable dependency.

Do not encode `if polls < N { starvation }` as general guidance.

## Stable Monitoring Loop

```rust
use std::time::Duration;
use tokio::runtime::RuntimeMetrics;
use tokio::sync::mpsc;

#[derive(Debug)]
struct Snapshot {
    alive_tasks: usize,
    global_queue_depth: usize,
}

fn spawn_metrics_collector(metrics: RuntimeMetrics) -> mpsc::Receiver<Snapshot> {
    let (tx, rx) = mpsc::channel(16);

    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(10));
        loop {
            interval.tick().await;
            let snapshot = Snapshot {
                alive_tasks: metrics.num_alive_tasks(),
                global_queue_depth: metrics.global_queue_depth(),
            };

            if tx.send(snapshot).await.is_err() {
                break;
            }
        }
    });

    rx
}

#[tokio::main]
async fn main() {
    let metrics = tokio::runtime::Handle::current().metrics();
    let mut snapshots = spawn_metrics_collector(metrics);

    if let Some(snapshot) = snapshots.recv().await {
        println!(
            "alive={} queued={}",
            snapshot.alive_tasks,
            snapshot.global_queue_depth
        );
    }
}
```

`RuntimeMetrics` is a clonable handle, so it can be moved into a monitoring task without borrowing the `Runtime` itself.

## `tokio-console`

For per-task/resource diagnostics, `tokio-console`/`console-subscriber` can provide much richer instrumentation than aggregate runtime counters. With Tokio it requires the runtime's tracing instrumentation and `tokio_unstable`; follow the current console documentation rather than assuming that enabling `RuntimeMetrics` automatically enables console data.

Aggregate metrics and task-level tracing serve different purposes and can be used together.

## Practical Guidance

- Start with stable metrics when they answer the operational question.
- Treat runtime metrics as observations, not diagnoses.
- Compare cumulative counters over intervals.
- Derive alert thresholds from service objectives and measured workload behavior.
- Gate `tokio_unstable` metrics explicitly and expect API churn.
- Correlate scheduler telemetry with application latency, throughput, and traces.

## See Also

- [async-blocking-detection](./async-blocking-detection.md) — Finding blocking async work
- [async-tokio-runtime](./async-tokio-runtime.md) — Runtime configuration
- [async-joinset-structured](./async-joinset-structured.md) — Task lifecycle management
