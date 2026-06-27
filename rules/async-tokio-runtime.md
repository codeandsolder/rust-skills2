# async-tokio-runtime

> Configure Tokio runtime appropriately for your workload

**Rule**: `async-tokio-runtime`

## Why It Matters

Tokio's default multi-threaded runtime isn't always optimal. CPU-bound work needs different configuration than IO-bound work. Incorrect configuration leads to poor performance, blocked workers, or resource exhaustion. Understanding runtime options lets you tune for your specific use case. In production, **runtime metrics** are essential for detecting starvation, blocking thread pressure, and task health.

## Bad

```rust
// Default runtime for everything - not optimal
#[tokio::main]
async fn main() {
    // CPU-heavy work on async executor starves IO tasks
    for data in datasets {
        let result = heavy_computation(data).await;
    }
}

// Single-threaded when multi-threaded is needed
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Can't utilize multiple cores for concurrent tasks
    for _ in 0..1000 {
        tokio::spawn(async { /* IO work */ });
    }
}

// No metrics monitoring in production
// -> No visibility into blocking, starvation, or task health
```

## Good

```rust
// Multi-threaded for concurrent IO (default)
#[tokio::main]
async fn main() {
    // Good for many concurrent network connections
    let handles: Vec<_> = urls.iter()
        .map(|url| tokio::spawn(fetch(url.clone())))
        .collect();
    
    futures::future::join_all(handles).await;
}

// Current-thread for single-threaded scenarios
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Good for single-connection clients, simpler debugging
    let client = Client::new();
    client.run().await;
}

// Custom configuration
#[tokio::main(worker_threads = 4)]
async fn main() {
    // Limit to 4 worker threads
}

// Or manual setup for more control
fn main() {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .thread_name("my-worker")
        .build()
        .unwrap();
    
    runtime.block_on(async_main());
}
```

## Runtime Types

| Runtime | Use Case | Configuration |
|---------|----------|---------------|
| Multi-thread | IO-bound, many connections | `#[tokio::main]` (default) |
| Current-thread | CLI tools, tests, single connection | `flavor = "current_thread"` |
| Custom | Fine-tuned performance | `Builder::new_*()` |

## Worker Thread Tuning

```rust
use tokio::runtime::Builder;

// IO-bound: more threads than cores can help
let io_runtime = Builder::new_multi_thread()
    .worker_threads(num_cpus::get() * 2)  // IO can benefit from oversubscription
    .max_blocking_threads(32)              // For spawn_blocking calls
    .thread_stack_size(2 * 1024 * 1024)    // 2MB stack per worker
    .enable_io()
    .enable_time()
    .build()?;

// CPU-bound: match core count
let cpu_runtime = Builder::new_multi_thread()
    .worker_threads(num_cpus::get())       // No benefit from more than cores
    .build()?;
```

## Advanced Builder Options

```rust
use tokio::runtime::Builder;

let runtime = Builder::new_multi_thread()
    .worker_threads(4)
    
    // Per-worker stack size (default: 2MB)
    .thread_stack_size(4 * 1024 * 1024)   // 4MB for deep call stacks
    
    // How often workers check the global queue (default: 61)
    // Lower values = better fairness, higher = better throughput
    .global_queue_interval(31)             // Check global queue every 31 local polls
    
    // Handle panics on async tasks (Tokio 1.36+)
    .unhandled_panic(tokio::runtime::UnhandledPanic::ShutdownRuntime)
    // Options:
    //   UnhandledPanic::Ignore (default) - task panics silently
    //   UnhandledPanic::ShutdownRuntime - panic stops the entire runtime
    
    .build()?;
```

### global_queue_interval

Controls how often worker threads check the global task queue (where tasks from `spawn` land). Lowering the value improves fairness across tasks at the cost of some throughput due to contention on the global queue.

### thread_stack_size

Sets the stack size for each worker thread. Default is 2MB. Increase for workloads with deep call stacks (e.g., recursive async parsers). Decrease for memory-constrained environments.

### UnhandledPanic (Tokio 1.36+)

```rust
use tokio::runtime::UnhandledPanic;

// Default: ignore - task panics don't affect other tasks
Builder::new_multi_thread()
    .unhandled_panic(UnhandledPanic::Ignore)
    .build()?;

// Shutdown runtime on any task panic
// Use for: run-to-completion systems, safety-critical apps
Builder::new_multi_thread()
    .unhandled_panic(UnhandledPanic::ShutdownRuntime)
    .build()?;
```

## RuntimeMetrics (requires `tokio_unstable`)

Runtime metrics require the `tokio_unstable` cfg flag. Add to `Cargo.toml`:

```toml
[dependencies]
tokio = { version = "1", features = ["rt", "macros", "rt-multi-thread"] }

[build-dependencies]
# Or in .cargo/config.toml:
# [build]
# rustflags = ["--cfg", "tokio_unstable"]
```

Then at build time (`.cargo/config.toml`):
```toml
[build]
rustflags = ["--cfg", "tokio_unstable"]
```

```rust
use tokio::runtime::RuntimeMetrics;

fn check_health(metrics: &RuntimeMetrics) {
    // Task health
    let active = metrics.num_alive_tasks();           // Currently executing tasks
    let remote = metrics.remote_schedule_count();    // Tasks scheduled from other threads
    
    // Blocking pool pressure
    let blocking_depth = metrics.blocking_queue_depth();  // Queued blocking tasks
    let blocking_threads = metrics.num_blocking_threads(); // Active blocking threads
    
    // Starvation detection
    let num_workers = metrics.num_workers();
    let total_poll_count: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();  // Total task polls across all workers
    
    if blocking_depth > 10 {
        warn!("Blocking pool saturated: {} queued", blocking_depth);
    }
    
    if remote > active * 100 {
        warn!("High remote scheduling - potential pinning issue");
    }
}

// Monitor periodically
async fn metrics_loop(metrics: RuntimeMetrics) {
    let mut interval = tokio::time::interval(Duration::from_secs(10));
    loop {
        interval.tick().await;
        let depth = metrics.blocking_queue_depth();
        let tasks = metrics.num_alive_tasks();
        if depth > 100 {
            error!("Blocking pool critical: {} queued, {} active tasks", depth, tasks);
        }
    }
}
```

### Key Metrics

| Metric | Returns | Purpose |
|--------|---------|---------|
| `num_alive_tasks()` | u64 | Number of tasks currently being polled |
| `blocking_queue_depth()` | usize | Number of tasks waiting in the blocking thread pool |
| `num_blocking_threads()` | usize | Current number of blocking threads |
| `worker_poll_count(worker)` | u64 | Number of polls on a specific worker (sum across workers for total) |
| `remote_schedule_count()` | u64 | Tasks scheduled from other threads |

## Multiple Runtimes

```rust
// Separate runtimes for different workloads
struct App {
    io_runtime: Runtime,
    cpu_runtime: Runtime,
}

impl App {
    fn new() -> Self {
        Self {
            io_runtime: Builder::new_multi_thread()
                .worker_threads(8)
                .thread_name("io-worker")
                .build()
                .unwrap(),
            cpu_runtime: Builder::new_multi_thread()
                .worker_threads(4)
                .thread_name("cpu-worker")
                .build()
                .unwrap(),
        }
    }
    
    fn spawn_io<F>(&self, future: F) 
    where F: Future + Send + 'static, F::Output: Send + 'static 
    {
        self.io_runtime.spawn(future);
    }
    
    fn spawn_cpu<F>(&self, task: F) 
    where F: FnOnce() + Send + 'static 
    {
        self.cpu_runtime.spawn_blocking(task);
    }
}
```

## Runtime in Tests

```rust
// Single test runtime
#[tokio::test]
async fn test_single() {
    assert!(true);
}

// Multi-threaded test
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_concurrent() {
    let (tx, rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move { tx.send(42).unwrap() });
    assert_eq!(rx.await.unwrap(), 42);
}

// Custom runtime in test
#[test]
fn test_with_custom_runtime() {
    let rt = Builder::new_current_thread().build().unwrap();
    rt.block_on(async {
        // test code
    });
}
```

## See Also

- [async-runtime-metrics](./async-runtime-metrics.md) - Deep dive into RuntimeMetrics
- [async-spawn-blocking](./async-spawn-blocking.md) - Handling blocking code
- [async-blocking-detection](./async-blocking-detection.md) - Detecting blocking in async
- [async-no-lock-await](./async-no-lock-await.md) - Avoiding lock issues
- [async-joinset-structured](./async-joinset-structured.md) - Managing spawned tasks
