# async-joinset-structured

> Use `JoinSet` for managing dynamic collections of spawned tasks with structured concurrency

**Rule**: `async-joinset-structured`

## Why It Matters

`JoinSet` is the **structured-concurrency king** of Tokio. It provides task lifecycle management—spawn, track, cancel, join—in one abstraction. Unlike `Vec<JoinHandle>` + `join_all`, `JoinSet` delivers results as they complete, supports dynamic addition/removal, and aborts all tasks on drop. Combined with `CancellationToken` and `select!`, it forms the 2026 recommended structured concurrency triad.

## Bad

```rust
// Manual handle management - inflexible and error-prone
let mut handles: Vec<JoinHandle<Result<Data>>> = Vec::new();

for url in urls {
    handles.push(tokio::spawn(fetch(url)));
}

// Wait for all, in order (not as they complete)
let results = futures::future::join_all(handles).await;

// No easy way to cancel all, handle errors progressively, or add more tasks
```

## Good

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

for url in urls {
    set.spawn(fetch(url.clone()));
}

// Process results as they complete
while let Some(result) = set.join_next().await {
    match result {
        Ok(Ok(data)) => process(data),
        Ok(Err(e)) => log::error!("Task failed: {}", e),
        Err(e) => log::error!("Task panicked: {}", e),
    }
}

// All tasks done, set is empty
```

## join_next_with_id (Tokio 1.38+)

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

let id_a = set.spawn(fetch("https://a.com"));
let id_b = set.spawn(fetch("https://b.com"));

// Get results with their spawn IDs
while let Some(result) = set.join_next_with_id().await {
    match result {
        Ok((id, Ok(data))) => {
            println!("Task {id} succeeded: {data:?}");
        }
        Ok((id, Err(e))) => {
            println!("Task {id} failed: {e}");
        }
        Err((id, e)) => {
            println!("Task {id} panicked: {e}");
        }
    }
}
```

`join_next_with_id()` returns the `Id` assigned at `spawn()` time, making it possible to correlate results with their originating tasks without manual index tracking.

## spawn_blocking (Tokio 1.38+)

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();

// Spawn CPU-bound work on the blocking thread pool
for data in datasets {
    set.spawn_blocking(move || {
        heavy_computation(data)
    });
}

while let Some(result) = set.join_next().await {
    // Process blocking results
}
```

`JoinSet::spawn_blocking()` works like `tokio::task::spawn_blocking()` but integrates with JoinSet's lifecycle management.

## Shutdown and Detach (Tokio 1.38+/1.40+)

```rust
use tokio::task::JoinSet;

let mut set = JoinSet::new();
set.spawn(long_task());
set.spawn(another_task());

// Option 1: Shutdown with timeout (Tokio 1.40+)
// Waits for all tasks to complete, then returns
tokio::time::timeout(
    Duration::from_secs(5),
    set.shutdown(),
).await.ok();

// Option 2: Detach all (Tokio 1.38+)
// Abort all tasks and forget them (no join needed)
set.detach_all();
// Tasks are aborted, set is empty - no need to drain

// Option 3: Abort and drain (traditional)
set.abort_all();
while set.join_next().await.is_some() {}  // Drain
```

`shutdown().await` is the cleanest—it awaits all tasks to finish naturally, aborting only on timeout. `detach_all()` is useful when you need to discard all tasks immediately.

## Dynamic Task Addition

```rust
use tokio::task::JoinSet;

async fn worker_pool(mut rx: mpsc::Receiver<Task>) {
    let mut set = JoinSet::new();
    let max_concurrent = 10;
    
    loop {
        tokio::select! {
            // Accept new tasks if under limit
            Some(task) = rx.recv(), if set.len() < max_concurrent => {
                set.spawn(process_task(task));
            }
            
            // Process completed tasks
            Some(result) = set.join_next() => {
                handle_result(result);
            }
            
            // Exit when no tasks and channel closed
            else => break,
        }
    }
}
```

## Concurrency-Limiting with Semaphore

```rust
use tokio::sync::Semaphore;
use tokio::task::JoinSet;

async fn crawl_urls(urls: &[String], max_concurrent: usize) {
    let semaphore = Arc::new(Semaphore::new(max_concurrent));
    let mut set = JoinSet::new();

    for url in urls {
        let permit = semaphore.clone().acquire_owned().await.unwrap();
        let url = url.clone();
        set.spawn(async move {
            let _permit = permit;  // Held until task completes
            fetch(&url).await
        });
    }

    while let Some(result) = set.join_next().await {
        // Process result
    }
    // All permits released when tasks complete
}
```

## Structured Concurrency Triad (2026)

JoinSet + CancellationToken + select! is the recommended pattern:

```rust
use tokio::task::JoinSet;
use tokio::select;
use tokio_util::sync::CancellationToken;

async fn managed_workload(shutdown: CancellationToken) {
    let mut set = JoinSet::new();

    // Spawn workers with child tokens
    for i in 0..4 {
        let token = shutdown.child_token();
        set.spawn(async move {
            loop {
                select! {
                    _ = token.cancelled() => break,
                    _ = do_work(i) => {},
                }
            }
        });
    }

    // Wait for shutdown or task failure
    select! {
        _ = shutdown.cancelled() => {
            // Graceful shutdown: wait for tasks to finish
            tokio::time::timeout(
                Duration::from_secs(30),
                set.shutdown(),
            ).await.ok();
        }
        Some(result) = set.join_next() => {
            // A task finished or panicked - cancel the rest
            shutdown.cancel();
            set.detach_all();
        }
    }
}
```

## Error Handling Pattern

```rust
use tokio::task::JoinSet;

async fn fetch_all(urls: &[String]) -> Vec<Result<Data, Error>> {
    let mut set = JoinSet::new();
    let mut results = Vec::new();
    
    for url in urls {
        set.spawn(fetch(url.clone()));
    }
    
    while let Some(join_result) = set.join_next().await {
        let result = match join_result {
            Ok(task_result) => task_result,
            Err(join_error) => {
                if join_error.is_panic() {
                    Err(Error::TaskPanicked)
                } else {
                    Err(Error::TaskCancelled)
                }
            }
        };
        results.push(result);
    }
    
    results
}
```

## Spawning with Context

```rust
use tokio::task::JoinSet;

let mut set: JoinSet<(usize, Result<Data, Error>)> = JoinSet::new();

for (index, url) in urls.iter().enumerate() {
    let url = url.clone();
    set.spawn(async move {
        (index, fetch(&url).await)
    });
}

// Results include their index
while let Some(result) = set.join_next().await {
    if let Ok((index, data)) = result {
        results[index] = Some(data);
    }
}
```

## Abort on Drop

```rust
use tokio::task::JoinSet;

{
    let mut set = JoinSet::new();
    set.spawn(long_running_task());
    set.spawn(another_task());
    
    // Early exit
    return;
}  // JoinSet dropped here - all tasks are aborted!

// Explicit abort
let mut set = JoinSet::new();
set.spawn(task());
set.abort_all();  // Cancel all tasks
```

## JoinSet vs join_all

| Feature | JoinSet | join_all |
|---------|---------|----------|
| Add tasks dynamically | Yes | No |
| Results as-completed | Yes | No (all at once) |
| Abort all on drop | Yes | No |
| Cancel all on demand | `abort_all()` / `detach_all()` | No |
| Per-task cancellation | Via `CancellationToken` per task | No |
| spawn_blocking support | Yes (1.38+) | No |
| Shutdown with timeout | Yes (1.40+) | No |
| Get IDs per task | Yes (1.38+) | No |
| Memory efficient | Yes | Pre-allocates |

## See Also

- [async-join-parallel](./async-join-parallel.md) - Static concurrent futures
- [async-cancellation-token](./async-cancellation-token.md) - Cancellation patterns
- [async-structured-concurrency](./async-structured-concurrency.md) - The JoinSet + CancellationToken + select! triad
- [async-try-join](./async-try-join.md) - Error handling in joins
