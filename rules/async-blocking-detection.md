# async-blocking-detection

> Detect async worker stalls with latency/console instrumentation; treat blocking-pool metrics as pool pressure, not proof that async workers are blocked

**Rule**: `async-blocking-detection`

## Why It Matters

Rust async executors are cooperatively scheduled. A future that calls a blocking API or performs a long CPU loop without yielding can occupy a runtime worker and delay unrelated tasks. On a current-thread runtime, one such operation can stop all async progress until it returns.

The important distinction is **where the blocking happens**:

- direct blocking inside a future stalls an async worker;
- `spawn_blocking` deliberately moves blocking work to Tokio's separate blocking pool;
- a deep `spawn_blocking` queue indicates pressure in that pool, not evidence that a future is directly blocking a worker.

Use development instrumentation such as `tokio-console`, application latency/heartbeat signals, and targeted profiling. Runtime metrics are useful context, but no single counter proves that a worker is stuck in synchronous code.

## Bad

```rust
use std::time::Duration;

async fn handle_request() {
    // BAD: this thread cannot poll other futures while sleeping.
    std::thread::sleep(Duration::from_secs(1));
}
```

The same problem applies to synchronous filesystem/network calls, long lock waits on blocking mutexes, FFI that blocks, and long compute loops that do not yield.

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

`spawn_blocking` is for synchronous operations that eventually finish. For many CPU-bound jobs, bound concurrency explicitly or use a CPU-oriented executor such as Rayon rather than allowing Tokio's large blocking pool to run an arbitrary number of computations at once.

## Good: External Heartbeat for Whole-Runtime Stalls

A watchdog running on an ordinary OS thread can observe whether an async heartbeat stops advancing even when the runtime itself is stalled:

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

A stalled heartbeat is still only a symptom: CPU starvation, process suspension, scheduler pressure, or an overloaded host can produce similar observations. Correlate it with profiles, task instrumentation, and workload metrics.

## `tokio-console` During Development

`tokio-console`/`console-subscriber` can expose task poll durations, long busy periods, and resource activity. It is particularly useful for finding tasks that spend too long between yielding points.

<!-- rust-check: fragment; reason=requires console-subscriber dependency and Tokio tracing instrumentation -->
```rust
#[tokio::main]
async fn main() {
    console_subscriber::init();
    run_app().await;
}
```

Use a build configured for the instrumentation required by the console and reproduce the real workload; a task that is never polled cannot be diagnosed from its source location by a magic runtime counter.

## Runtime Metrics: What They Do and Do Not Mean

Stable `RuntimeMetrics` includes useful values such as worker count and alive-task count:

```rust
async fn report_basic_metrics() {
    let metrics = tokio::runtime::Handle::current().metrics();
    println!("workers={}", metrics.num_workers());
    println!("alive_tasks={}", metrics.num_alive_tasks());
}
```

Many more detailed scheduler and blocking-pool metrics remain behind Tokio's `tokio_unstable` configuration. In particular, `num_blocking_threads` and blocking-pool queue metrics describe work submitted **to the blocking pool**. A growing queue can indicate that `spawn_blocking`, filesystem, DNS, or other blocking-pool users are saturated; it does not detect `std::thread::sleep` executed directly on an async worker.

## `block_in_place` Is Specialized

`tokio::task::block_in_place` tells the multi-thread runtime that the current task is about to block so Tokio can hand other tasks to another worker. The closure still blocks its current thread, all concurrent code inside that same task is suspended, and it is not available on a current-thread runtime.

Prefer `spawn_blocking` when the synchronous work can naturally be moved into a `'static` closure. Use `block_in_place` only when its specific execution semantics are required.

## Blocking-Pool Configuration

Tokio's blocking-thread limit is intentionally large by default because the pool serves APIs such as filesystem operations and DNS resolution as well as explicit `spawn_blocking` calls. Setting `max_blocking_threads` too low can create an unbounded queue and delay unrelated blocking-pool users.

Do not lower the limit merely to make queue depth easier to alert on. Bound a CPU-heavy workload at its own admission point (for example with a semaphore or CPU pool), and size runtime limits from measured workload behavior.

## Review Checklist

Look for:

- `std::thread::sleep` inside async code;
- synchronous filesystem/network/database clients on async workers;
- blocking mutex/RwLock acquisition held across slow operations;
- FFI whose blocking behavior is unknown;
- long loops without `.await`, cooperative yielding, or offloading;
- large `spawn_blocking` bursts without workload-level backpressure.

Then validate suspected paths with traces/profiles rather than inferring causality from one metric.

## See Also

- [async-spawn-blocking](./async-spawn-blocking.md) — moving blocking work off workers
- [async-tokio-runtime](./async-tokio-runtime.md) — runtime configuration
- [async-runtime-metrics](./async-runtime-metrics.md) — runtime metrics

## References

- [Tokio `spawn_blocking`](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)
- [Tokio `RuntimeMetrics`](https://docs.rs/tokio/latest/tokio/runtime/struct.RuntimeMetrics.html)
- [Tokio runtime `Builder`](https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html)
- [tokio-console](https://github.com/tokio-rs/console)
