# async-tokio-runtime

> Start with Tokio's default runtime configuration; choose runtime flavor and tuning from execution requirements and measurements

**Rule**: `async-tokio-runtime`

## Why It Matters

Tokio has separate async worker threads and a blocking thread pool. Runtime configuration changes scheduling, memory use, failure modes, and the capacity available to APIs such as `spawn_blocking` and `tokio::fs`.

Most applications should begin with Tokio's defaults. The multi-thread runtime defaults its worker count to the number of cores available to the process, and Tokio explicitly advises keeping custom worker counts on the smaller side. Arbitrarily doubling workers for “I/O-bound” code is not a general optimization: readiness-based async I/O does not require one worker per blocked operation.

CPU-heavy synchronous work is also not fixed by creating more Tokio workers. Keep long compute off async workers and use workload-level bounds or a CPU-oriented executor where appropriate.

## Bad: Tuning by Folklore

```rust
use tokio::runtime::Builder;

fn build_runtime() -> tokio::runtime::Runtime {
    Builder::new_multi_thread()
        .worker_threads(64)        // arbitrary oversubscription
        .max_blocking_threads(32)  // arbitrary global blocking-pool cap
        .enable_all()
        .build()
        .unwrap()
}
```

A low blocking-thread cap can queue filesystem, DNS, standard-stream, and explicit `spawn_blocking` work together. A high async worker count can add scheduling and memory overhead without improving throughput.

## Good: Start from the Execution Model

```rust
use tokio::runtime::{Builder, Runtime};

fn build_server_runtime() -> Runtime {
    Builder::new_multi_thread()
        .enable_all()
        .thread_name("app-worker")
        .build()
        .unwrap()
}

fn build_single_thread_runtime() -> Runtime {
    Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
```

Use the multi-thread runtime when tasks should be able to execute across worker threads. Use `current_thread` when single-thread execution is an intentional property—for example a small local executor, deterministic integration boundary, or `!Send` work driven through an appropriate local task mechanism.

A current-thread runtime does **not** make blocking calls less harmful: direct blocking stops its only async worker.

## `#[tokio::main]`

For ordinary applications, the macro is often enough:

```rust
#[tokio::main]
async fn main() {
    tokio::task::yield_now().await;
}
```

Choose an explicit flavor only when it encodes a real requirement:

```rust
#[tokio::main(flavor = "current_thread")]
async fn main() {
    tokio::task::yield_now().await;
}
```

Avoid setting `worker_threads = N` merely because a machine happens to have N or 2N cores. Measure the target deployment and understand which work actually runs on async workers.

## Worker Threads vs Blocking Threads

| Setting | Controls | Default/behavior |
|---------|----------|------------------|
| `worker_threads(n)` | Multi-thread async scheduler workers | defaults to available cores; no effect on current-thread runtime |
| `max_blocking_threads(n)` | Additional blocking-pool threads | large default (512 in current Tokio); blocking work queues after the cap |
| `thread_keep_alive` | Idle blocking-thread lifetime | affects blocking pool, not async worker count |
| `thread_stack_size` | stack size for runtime-created threads | tune only for demonstrated stack/memory needs |

The blocking queue has no built-in backpressure. If a CPU workload can submit thousands of `spawn_blocking` jobs, bound that workload explicitly rather than relying on the runtime-wide maximum thread count.

## CPU-Bound Work

```rust
async fn hash_blob(data: Vec<u8>) -> Result<u64, tokio::task::JoinError> {
    tokio::task::spawn_blocking(move || {
        data.into_iter()
            .fold(0u64, |acc, byte| acc.wrapping_mul(16777619) ^ u64::from(byte))
    })
    .await
}
```

This is acceptable for bounded blocking/compute work. For many sustained CPU jobs, use a semaphore or other admission control, or a CPU-oriented pool such as Rayon. A second Tokio runtime whose `worker_threads` are configured and then used only via `spawn_blocking` is conceptually wrong: `spawn_blocking` uses that runtime's **separate blocking pool**, not its async worker count.

## Stable Runtime Metrics

Basic runtime metrics are available through a runtime/handle without `tokio_unstable`:

```rust
async fn report_runtime() {
    let metrics = tokio::runtime::Handle::current().metrics();
    println!("workers={}", metrics.num_workers());
    println!("alive_tasks={}", metrics.num_alive_tasks());
}
```

Use these as observations, not magic thresholds. `num_alive_tasks` can be only weakly consistent on a multi-thread runtime.

More detailed metrics—including several blocking-pool and per-worker counters—remain behind Tokio's `tokio_unstable` configuration. If production monitoring depends on an unstable metric, isolate that dependency and expect API changes.

## Unhandled Task Panics

Tokio's default behavior is to forward a spawned task's panic to its `JoinHandle` while allowing the runtime and other tasks to continue.

`Builder::unhandled_panic` is currently a `tokio_unstable` API. In particular, `UnhandledPanic::ShutdownRuntime` is only supported for the current-thread runtime; applying it to a multi-thread runtime panics. Do not present it as a stable generic “safety-critical runtime” switch.

For critical tasks, explicitly observe `JoinHandle` results or use structured task ownership so failures cannot disappear simply because a handle was dropped.

## Advanced Scheduler Knobs

Settings such as `global_queue_interval`, event intervals, stack size, histogram configuration, and callbacks can be useful for specialized workloads, but their optimal values are workload- and Tokio-version-dependent.

Do not encode rules such as “31 is fairer than 61” or “I/O needs 2× cores” as universal guidance. Benchmark realistic load and monitor tail latency, throughput, CPU utilization, queue pressure, and memory together.

## Multiple Runtimes

Multiple Tokio runtimes can be justified by isolation requirements, ownership boundaries, or embedding constraints, but they add threads, timers, I/O drivers, shutdown semantics, and cross-runtime coordination. Prefer one runtime plus explicit workload isolation unless a separate runtime solves a measured or architectural problem.

## Runtime in Tests

```rust
#[tokio::test]
async fn default_async_test() {
    tokio::task::yield_now().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_that_requires_multiple_workers() {
    let handle = tokio::spawn(async { 42 });
    assert_eq!(handle.await.unwrap(), 42);
}
```

Use a multi-thread test only when the behavior under test actually requires it; more workers do not make a test inherently more realistic.

## See Also

- [async-runtime-metrics](./async-runtime-metrics.md) — metrics details and stability
- [async-spawn-blocking](./async-spawn-blocking.md) — blocking/CPU work
- [async-blocking-detection](./async-blocking-detection.md) — finding worker stalls
- [async-joinset-structured](./async-joinset-structured.md) — task ownership

## References

- [Tokio runtime `Builder`](https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html)
- [Tokio `RuntimeMetrics`](https://docs.rs/tokio/latest/tokio/runtime/struct.RuntimeMetrics.html)
- [Tokio `spawn_blocking`](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)
