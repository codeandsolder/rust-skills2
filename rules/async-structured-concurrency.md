# async-structured-concurrency

> Combine `JoinSet` + `CancellationToken` + `select!` for structured async task management

**Rule**: `async-structured-concurrency`

## Why It Matters

In unstructured concurrency, spawned tasks outlive their parent scope, making it hard to guarantee cleanup, cancellation, or resource release. The 2026 recommended pattern uses three Tokio primitives together:

1. **`JoinSet`** — tracks task lifecycle and aborts on drop
2. **`CancellationToken`** — signals shutdown cooperatively
3. **`select!`** — races between shutdown, work, and completion

This triad ensures that when a scope exits, all tasks spawned within it are either completed, cancelled, or detached—never orphaned.

## The Triad Pattern

```rust
use tokio::task::JoinSet;
use tokio::select;
use tokio_util::sync::CancellationToken;

async fn managed_scope(shutdown: CancellationToken) {
    let mut set = JoinSet::new();

    // Spawn work with child tokens
    for i in 0..5 {
        let token = shutdown.child_token();
        set.spawn(async move {
            worker_loop(i, token).await;
        });
    }

    // Race between shutdown and task completion
    select! {
        _ = shutdown.cancelled() => {
            // Graceful shutdown
            tokio::time::timeout(
                Duration::from_secs(10),
                set.shutdown(),
            ).await.ok();
        }
        Some(result) = set.join_next() => {
            // A task finished (or panicked) - cancel the rest
            shutdown.cancel();
            set.detach_all();
        }
    }
}

async fn worker_loop(id: usize, token: CancellationToken) {
    loop {
        select! {
            _ = token.cancelled() => {
                cleanup(id).await;
                break;
            }
            _ = do_work(id) => {}
        }
    }
}
```

## Hierarchy with child_token

```rust
use tokio_util::sync::CancellationToken;

// Parent token controls the entire subsystem
let parent = CancellationToken::new();

// Child tokens: cancelled when parent is cancelled
// Each child can also be independently cancelled
let child_a = parent.child_token();
let child_b = parent.child_token();

// Cancel the parent — all children are also cancelled
parent.cancel();
```

## CancellationToken + select! with biased;

When prioritizing shutdown, use `biased;` to check cancellation first:

```rust
use tokio::select;
use tokio_util::sync::CancellationToken;

async fn prioritized_loop(token: CancellationToken) {
    loop {
        select! {
            biased;  // Check cancellation first every iteration
            _ = token.cancelled() => {
                cleanup().await;
                break;
            }
            result = process_next() => {
                handle(result);
            }
        }
    }
}
```

## JoinSet::shutdown vs drain

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
set.spawn(task_a());
set.spawn(task_b());

// Graceful: wait for tasks to complete naturally (Tokio 1.40+)
set.shutdown().await;
// All tasks completed or cancelled

// Forceful: abort all immediately
set.abort_all();
while set.join_next().await.is_some() {} // Drain aborted results

// Detach: abort and forget (Tokio 1.38+)
set.detach_all();
// No need to drain - set is empty immediately
```

## Concurrency-Limited JoinSet

For workloads where you need to limit concurrency while maintaining structured lifecycle:

```rust
use tokio::task::JoinSet;
use tokio::sync::Semaphore;

async fn concurrent_crawl(
    urls: Vec<String>,
    max_concurrent: usize,
    shutdown: CancellationToken,
) {
    let semaphore = Arc::new(Semaphore::new(max_concurrent));
    let mut set = JoinSet::new();

    for url in urls {
        // Wait for semaphore permit
        let permit = semaphore.clone().acquire_owned().await.unwrap();
        let token = shutdown.child_token();
        
        set.spawn(async move {
            let _permit = permit; // Held until task finishes
            select! {
                _ = token.cancelled() => {},
                result = fetch(&url) => result,
            }
        });
    }

    // Wait for all tasks with shutdown
    select! {
        _ = shutdown.cancelled() => {
            set.shutdown().await;
        }
        _ = async { while set.join_next().await.is_some() {} } => {}
    }
}
```

## Using bounded_join_set Crate

For simple concurrency-limited JoinSet, consider the `bounded_join_set` crate:

```rust
// use bounded_join_set::BoundedJoinSet;

// let mut set = BoundedJoinSet::new(10);  // Max 10 concurrent tasks
// set.spawn(task_a());
// set.spawn(task_b());
// // Automatically limits to 10 tasks
// while let Some(result) = set.join_next().await { ... }
```

## The Full Lifecycle

```rust
use tokio::task::JoinSet;
use tokio::select;
use tokio_util::sync::CancellationToken;

async fn run_service(shutdown: CancellationToken) {
    let mut set = JoinSet::new();
    
    // Phase 1: Startup - spawn all tasks
    for component in &components {
        let token = shutdown.child_token();
        set.spawn(run_component(component, token));
    }
    
    // Phase 2: Operate - wait for shutdown or failure
    select! {
        _ = shutdown.cancelled() => {
            info!("Shutdown requested");
        }
        Some(result) = set.join_next() => {
            match result {
                Ok(Ok(())) => info!("Component completed"),
                Ok(Err(e)) => error!("Component failed: {}", e),
                Err(je) => error!("Component panicked: {}", je),
            }
            // Cancel remaining tasks
            shutdown.cancel();
        }
    }
    
    // Phase 3: Shutdown - graceful with timeout
    tokio::time::timeout(
        Duration::from_secs(30),
        set.shutdown(),
    ).await.ok();
    
    info!("Service shut down");
}
```

## When to Use This Pattern

Use the JoinSet + CancellationToken + select! triad when:
- Spawning multiple long-lived worker tasks
- Tasks need graceful shutdown
- You need to react to task panics/failures
- Resources must be cleaned up when the scope exits
- Concurrency needs to be limited

For simple cases (one-off spawns, fire-and-forget), the full pattern may be overkill.

## See Also

- [async-joinset-structured](./async-joinset-structured.md) — JoinSet deep dive
- [async-cancellation-token](./async-cancellation-token.md) — Cancellation patterns
- [async-select-racing](./async-select-racing.md) — select! patterns

## References

- [JoinSet docs](https://docs.rs/tokio/latest/tokio/task/join_set/struct.JoinSet.html)
- [CancellationToken docs](https://docs.rs/tokio-util/latest/tokio_util/sync/struct.CancellationToken.html)
- [async-joinset-structured](./async-joinset-structured.md) - JoinSet deep dive
- [async-cancellation-token](./async-cancellation-token.md) - Cancellation patterns
- [async-select-racing](./async-select-racing.md) - select! patterns
- [bounded_join_set crate](https://crates.io/crates/bounded-join-set)
