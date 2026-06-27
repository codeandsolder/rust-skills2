# async-blocking-detection

> Detect and prevent blocking in async code using `RuntimeMetrics` and runtime configuration

**Rule**: `async-blocking-detection`

## Why It Matters

Blocking in async is the #1 production mistake in Rust async systems. A single `std::thread::sleep`, synchronous mutex hold, or CPU-intensive loop on an async worker thread stalls the entire task scheduler. Because tasks are cooperatively scheduled, blocking doesn't cause crashes—it causes starvation that is hard to diagnose. Runtime metrics and configuration options now make blocking observable.

## Bad

```rust
use tokio::runtime::Runtime;

fn main() {
    let rt = Runtime::new().unwrap();
    rt.block_on(async {
        // BAD: Blocks the async worker thread
        std::thread::sleep(std::time::Duration::from_secs(5));
        
        // No metrics, no detection, no alerting
        // This starves ALL other tasks on this thread
    });
}
```

## Good

```rust
use tokio::runtime::{Builder, RuntimeMetrics};

fn main() {
    let rt = Builder::new_multi_thread()
        .worker_threads(4)
        .build()
        .unwrap();
    
    let metrics = rt.metrics();
    
    // Monitor blocking pool pressure
    rt.spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            
            // Rising blocking queue depth = tasks are blocking
            let depth = metrics.blocking_queue_depth();
            let blocking_threads = metrics.num_blocking_threads();
            
            if depth > 0 {
                warn!("Blocking on async: {} tasks queued, {} blocking threads active",
                    depth, blocking_threads);
            }
            
            if depth > 10 {
                error!("CRITICAL: High blocking pressure in async runtime");
            }
        }
    });
    
    rt.block_on(async { /* application */ });
}
```

## Using UnhandledPanic for Detection

```rust
use tokio::runtime::{Builder, UnhandledPanic};

// Option A: Shutdown runtime on panic (discover blocking via crashes)
let rt = Builder::new_multi_thread()
    .unhandled_panic(UnhandledPanic::ShutdownRuntime)
    .build()
    .unwrap();
// Any task panic = entire runtime shuts down
// Useful in safety-critical systems

// Option B: Default (ignore) + metrics monitoring
let rt = Builder::new_multi_thread()
    .unhandled_panic(UnhandledPanic::Ignore)
    .build()
    .unwrap();
// Tasks panic silently, metrics reveal the symptoms
```

## Metrics-Based Detection

```rust
use tokio::runtime::RuntimeMetrics;

async fn detect_blocking(metrics: &RuntimeMetrics) {
    let mut prev_blocking = metrics.blocking_queue_depth();
    let num_workers = metrics.num_workers();
    let mut prev_polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
    
    loop {
        tokio::time::sleep(Duration::from_secs(1)).await;
        
        // Signal 1: Blocking queue depth grows
        let depth = metrics.blocking_queue_depth();
        if depth > prev_blocking + 5 {
            warn!("Blocking tasks accumulating: depth {}", depth);
        }
        prev_blocking = depth;
        
        // Signal 2: Poll count stagnates while tasks are active
        let num_workers = metrics.num_workers();
        let polls: u64 = (0..num_workers).map(|w| metrics.worker_poll_count(w)).sum();
        let delta_polls = polls - prev_polls;
        let active = metrics.num_alive_tasks();
        
        if delta_polls < 5 && active > 5 {
            warn!("Possible starvation: only {} polls with {} active tasks",
                delta_polls, active);
        }
        prev_polls = polls;
    }
}
```

## Fixing Blocking Code

```rust
use tokio::task;

// BAD: Direct blocking
async fn bad() {
    std::thread::sleep(Duration::from_secs(1));  // Blocks!
}

// GOOD: spawn_blocking
async fn good() {
    task::spawn_blocking(move || {
        std::thread::sleep(Duration::from_secs(1));
    }).await.unwrap();
}

// ALTERNATIVE: block_in_place (for unavoidable sync boundaries)
async fn alternative() {
    task::block_in_place(move || {
        // Temporarily removes the task from the scheduler
        std::thread::sleep(Duration::from_secs(1));
    });
}
```

## block_in_place vs spawn_blocking

```rust
use tokio::task;

// spawn_blocking: runs on the blocking thread pool
// Use for: CPU-intensive work, long-running sync operations
// Does not block worker threads at all
async fn blocking() {
    task::spawn_blocking(|| {
        expensive_sync_work()
    }).await.unwrap();
}

// block_in_place: runs on the current thread but yields
// Use for: sync FFI calls, short blocking operations
// Temporarily allows blocking on the worker thread
async fn in_place() {
    task::block_in_place(|| {
        // The worker thread can run other tasks while we block
        sync_ffi_call()
    });
}
```

## Detecting Blocking at Development Time

```rust
// Use tokio-console to visualize blocking:
// 1. Add console-subscriber dependency
// 2. Initialize early in main()
// 3. Run tokio-console in another terminal

#[tokio::main]
async fn main() {
    console_subscriber::init();
    // Tasks that block will be visible in the console UI
    run_app().await;
}
```

## Configuration: max_blocking_threads

```rust
use tokio::runtime::Builder;

// Default: 512 max blocking threads
// If you see blocking_queue_depth growing, cap it:
let rt = Builder::new_multi_thread()
    .worker_threads(4)
    .max_blocking_threads(64)  // Explicit cap
    .build()?;

// A saturated blocking pool is a strong signal
// that tasks are blocking instead of using spawn_blocking
```

## See Also

- [async-runtime-metrics](./async-runtime-metrics.md) — RuntimeMetrics deep dive
- [async-spawn-blocking](./async-spawn-blocking.md) — spawn_blocking patterns
- [async-tokio-runtime](./async-tokio-runtime.md) — Runtime configuration

## References

- [RuntimeMetrics docs](https://docs.rs/tokio/latest/tokio/runtime/struct.RuntimeMetrics.html)
- [RuntimeBuilder docs](https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html)
- [async-runtime-metrics](./async-runtime-metrics.md) - RuntimeMetrics deep dive
- [async-spawn-blocking](./async-spawn-blocking.md) - spawn_blocking patterns
- [async-tokio-runtime](./async-tokio-runtime.md) - Runtime configuration
- [tokio-console](https://github.com/tokio-rs/console)
