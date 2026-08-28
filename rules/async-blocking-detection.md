# async-blocking-detection

> Detect async worker stalls with latency/console instrumentation; treat blocking-pool metrics as pool pressure, not proof that async workers are blocked

**Rule**: `async-blocking-detection`

## Why It Matters

Rust async executors are cooperatively scheduled. A future that calls a blocking API or performs a long CPU loop without yielding can occupy a runtime worker and delay unrelated tasks. On a current-thread runtime, one such operation can stop all async progress until it returns.

Distinguish the execution domains:

- direct blocking inside a future stalls an async worker;
- `spawn_blocking` moves synchronous work to Tokio's separate blocking pool;
- a deep blocking-pool queue means that pool is under pressure, not that an async worker is directly blocked.

Use task/runtime instrumentation, application latency or heartbeat signals, and targeted profiling together. No single runtime counter identifies the source of every stall.

## Bad

```rust
use std::time::Duration;

async fn handle_request() {
    std::thread::sleep(Duration::from_secs(1));
}
```

The same concern applies to synchronous filesystem/network calls, blocking FFI, blocking lock acquisition, and long compute loops that do not yield.

## Good: Move Blocking Work Off Async Workers

```rust
use std::time::Duration;

async fn handle_request() -> Result<u64, tokio::task::JoinError> {
    tokio::task::spawn_blocking(|| {
        std::thread::sleep(Duration::from_millis(10));
        42u64
    })
    .await
}
```

`spawn_blocking` is for synchronous operations that eventually finish. Bound concurrency separately when many CPU-heavy jobs could otherwise occupy the large blocking pool simultaneously.

## External Heartbeat for Whole-Runtime Stalls

A watchdog on an ordinary OS thread can observe whether an async heartbeat stops advancing even if the runtime itself is stalled:

```rust
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use std::time::Duration;

async fn runtime_heartbeat(counter: Arc<AtomicU64>) {
    let mut tick = tokio::time::interval(Duration::from_millis(100));
    loop {
        tick.tick().await;
        counter.fetch_add(1, Ordering::Relaxed);
    }
}

fn start_watchdog(counter: Arc<AtomicU64>) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let mut previous = counter.load(Ordering::Relaxed);
        loop {
            std::thread::sleep(Duration::from_secs(1));
            let current = counter.load(Ordering::Relaxed);
            if current == previous {
                eprintln!("async runtime heartbeat made no progress");
            }
            previous = current;
        }
    })
}
```

A stalled heartbeat is a symptom, not a diagnosis: host scheduler pressure, process suspension, CPU starvation, or executor stalls can all produce it.

## `tokio-console` During Development

`tokio-console`/`console-subscriber` can expose task poll durations, long busy periods, and resource activity. It requires the console subscriber dependency plus the Tokio/tracing instrumentation configuration expected by that tool, so this repository's generic example crate does not compile-check the setup snippet itself.

<!-- rust-check: ignore; reason=requires console-subscriber plus the Tokio tracing instrumentation configuration used by tokio-console -->
```rust
#[tokio::main]
async fn main() {
    console_subscriber::init();
    run_app().await;
}
```

Treat that as deployment/setup documentation; compile-check the application's actual console configuration in the application that enables it.

## Runtime Metrics: Context, Not a Blocking Detector

Stable `RuntimeMetrics` includes values such as worker count and alive-task count:

```rust
async fn report_basic_metrics() {
    let metrics = tokio::runtime::Handle::current().metrics();
    println!("workers={}", metrics.num_workers());
    println!("alive_tasks={}", metrics.num_alive_tasks());
}
```

More detailed scheduler and blocking-pool metrics may require Tokio's unstable instrumentation configuration. Blocking-pool thread/queue metrics describe work submitted to that pool; they do not detect `std::thread::sleep` executed directly on an async worker.

## `block_in_place` Is Specialized

`tokio::task::block_in_place` tells the multi-thread runtime that the current task is about to block so Tokio can hand other tasks to another worker. The closure still blocks its thread, concurrent work inside that same task is suspended, and the API is not available on a current-thread runtime.

Prefer `spawn_blocking` when the work can naturally be moved into an owned closure. Use `block_in_place` only when its specific execution semantics are required.

## Review Checklist

Look for:

- `std::thread::sleep` inside async code;
- synchronous filesystem/network/database clients on async workers;
- blocking mutex/RwLock acquisition around slow work;
- FFI whose blocking behavior is unknown;
- long loops without `.await`, cooperative yielding, or offloading;
- large `spawn_blocking` bursts without workload-level backpressure.

Then validate suspected paths with traces/profiles rather than inferring causality from one metric.

## See Also

- [async-spawn-blocking](./async-spawn-blocking.md) — moving blocking work off workers
- [async-tokio-runtime](./async-tokio-runtime.md) — runtime configuration
- [async-runtime-metrics](./async-runtime-metrics.md) — runtime metrics
