# async-spawn-blocking

> Use `spawn_blocking` for blocking synchronous work; bound CPU-heavy work or use a dedicated CPU pool such as Rayon

## Why It Matters

Tokio executor workers must keep polling many async tasks. A blocking syscall or long synchronous computation on a worker can delay unrelated futures.

`tokio::task::spawn_blocking` moves synchronous blocking work to Tokio's blocking pool. That is a good fit for blocking APIs and short-to-moderate synchronous operations. It is not automatically the right scheduler for an unbounded stream of CPU-heavy jobs.

## Blocking API

```rust
use std::path::PathBuf;

async fn read_with_sync_library(path: PathBuf) -> std::io::Result<Vec<u8>> {
    tokio::task::spawn_blocking(move || sync_library::read_file(path))
        .await
        .expect("blocking task panicked")
}
```

When an async-native API exists, prefer it when appropriate:

```rust
async fn read_file(path: &std::path::Path) -> std::io::Result<Vec<u8>> {
    tokio::fs::read(path).await
}
```

## CPU-Heavy Work: Add Backpressure or a CPU Pool

Tokio permits a large number of blocking threads because the blocking pool also serves blocking I/O. Submitting many CPU-bound jobs without a bound can oversubscribe the machine.

```rust
use std::sync::Arc;
use tokio::sync::Semaphore;

async fn run_cpu_job(limit: Arc<Semaphore>, input: Input) -> Output {
    let permit = limit.acquire_owned().await.unwrap();
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        heavy_computation(input)
    })
    .await
    .expect("CPU job panicked")
}
```

For sustained parallel CPU workloads, a dedicated CPU executor such as Rayon is often a better model.

## No Universal Microsecond Threshold

There is no generally valid rule such as "under 10 µs stays async, over 1 ms must use `spawn_blocking`". The right boundary depends on runtime latency goals, concurrency, hardware, batching, and the cost of scheduling/offloading.

Measure under realistic load.

## Cancellation and Long-Lived Work

Once a `spawn_blocking` task has started, aborting its `JoinHandle` does not stop the underlying closure. Design explicit cancellation inside long computations if required.

For persistent blocking loops or long-lived dedicated services, a dedicated thread can be clearer than occupying a blocking-pool thread indefinitely.

## Runtime Tuning

`worker_threads` configures Tokio's async worker pool; `max_blocking_threads` configures the separate blocking pool. Do not tune one expecting it to control the other.

Avoid magic defaults such as "start at 64". Tune only when metrics and workload characteristics justify it.

## Key Points

- Blocking synchronous API → `spawn_blocking` is usually appropriate.
- Many CPU-heavy tasks → bound concurrency or use a dedicated CPU pool.
- `worker_threads` and blocking threads are different pools.
- Started blocking tasks are not cancellable merely by aborting the async handle.
- Measure latency and throughput rather than using universal duration thresholds.

## See Also

- [async-tokio-fs](async-tokio-fs.md) — async filesystem APIs
- [async-no-lock-await](async-no-lock-await.md) — blocking versus async synchronization
- [`tokio::task::spawn_blocking`](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)
