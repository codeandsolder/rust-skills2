# async-joinset-structured

> Use `JoinSet` to track a dynamic collection of Tokio tasks when completion order and lifecycle control matter

## Why It Matters

`tokio::task::JoinSet<T>` owns a set of spawned tasks with one output type. It is useful when tasks are added dynamically and results should be handled as tasks finish rather than in spawn order.

Its lifecycle semantics are important:

- dropping a `JoinSet` aborts every task still in the set;
- `abort_all()` requests abortion but leaves tasks in the set so they can be joined;
- `shutdown().await` aborts all tasks and drains the set;
- `detach_all()` removes tasks **without aborting them**, so they continue running in the background.

Do not use `shutdown()` as a synonym for “ask tasks to finish gracefully,” and do not use `detach_all()` as a synonym for cancellation.

## Good: Process Tasks as They Finish

```rust
use std::time::Duration;
use tokio::task::JoinSet;

async fn work(id: u64, delay_ms: u64) -> u64 {
    tokio::time::sleep(Duration::from_millis(delay_ms)).await;
    id
}

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    set.spawn(work(1, 20));
    set.spawn(work(2, 5));

    let mut completed = Vec::new();
    while let Some(result) = set.join_next().await {
        completed.push(result.unwrap());
    }

    assert_eq!(completed, vec![2, 1]);
}
```

`join_next()` returns whichever task completes next. The set is empty after all results have been joined.

## Join Errors and Task IDs

```rust
use tokio::task::JoinSet;

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    set.spawn(async { 7_u32 });

    match set.join_next_with_id().await {
        Some(Ok((id, value))) => {
            println!("task {id} returned {value}");
        }
        Some(Err(error)) => {
            println!("task {} failed: {error}", error.id());
        }
        None => {}
    }
}
```

`join_next_with_id()` returns `Result<(Id, T), JoinError>`. On the error path, the task ID is obtained from `JoinError::id()`; the error is not an `(Id, JoinError)` tuple.

## `abort_all`, `shutdown`, and `detach_all` Are Different

```rust
use tokio::task::JoinSet;

async fn pending_forever() {
    std::future::pending::<()>().await;
}

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    set.spawn(pending_forever());
    set.spawn(pending_forever());

    set.abort_all();

    // Aborted tasks remain in the set until joined.
    let mut joined = 0;
    while let Some(result) = set.join_next().await {
        assert!(result.unwrap_err().is_cancelled());
        joined += 1;
    }
    assert_eq!(joined, 2);
}
```

`shutdown().await` is the convenience operation for aborting and then draining:

```rust
use tokio::task::JoinSet;

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    set.spawn(std::future::pending::<()>());

    set.shutdown().await;
    assert!(set.is_empty());
}
```

By contrast, `detach_all()` deliberately gives up ownership of the tasks:

```rust
use tokio::task::JoinSet;

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    set.spawn(async {});

    set.detach_all();
    assert!(set.is_empty());
}
```

Detached tasks are not aborted by this call and are no longer controlled by that `JoinSet`.

## Graceful Shutdown Requires a Cooperative Signal

If tasks should run cleanup before a hard deadline, signal them cooperatively first, join them, and only abort after the deadline expires:

```rust
use std::time::Duration;
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

async fn worker(cancel: CancellationToken) {
    cancel.cancelled().await;
    tokio::time::sleep(Duration::from_millis(5)).await;
}

#[tokio::main]
async fn main() {
    let cancel = CancellationToken::new();
    let mut set = JoinSet::new();

    for _ in 0..4 {
        set.spawn(worker(cancel.clone()));
    }

    cancel.cancel();

    let graceful = tokio::time::timeout(Duration::from_secs(1), async {
        while set.join_next().await.is_some() {}
    })
    .await
    .is_ok();

    if !graceful {
        set.abort_all();
        while set.join_next().await.is_some() {}
    }
}
```

Calling `set.shutdown().await` at the start would skip the cooperative phase because `shutdown()` aborts tasks immediately.

## Dynamic Concurrency Limit

A `JoinSet` can itself provide the bookkeeping for a simple dynamic concurrency limit:

```rust
use tokio::task::JoinSet;

async fn process(value: u32) -> u32 {
    value * 2
}

#[tokio::main]
async fn main() {
    let inputs = 0_u32..20;
    let mut inputs = inputs.into_iter();
    let mut set = JoinSet::new();
    let limit = 4;
    let mut outputs = Vec::new();

    loop {
        while set.len() < limit {
            let Some(value) = inputs.next() else {
                break;
            };
            set.spawn(process(value));
        }

        match set.join_next().await {
            Some(result) => outputs.push(result.unwrap()),
            None => break,
        }
    }

    assert_eq!(outputs.len(), 20);
}
```

For streaming inputs, a `select!` loop or a semaphore may fit better. The main requirement is to keep the concurrency bound explicit.

## `spawn_blocking`

`JoinSet::spawn_blocking()` tracks blocking-pool jobs in the same set:

```rust
use tokio::task::JoinSet;

#[tokio::main]
async fn main() {
    let mut set = JoinSet::new();
    for value in 1_u64..=3 {
        set.spawn_blocking(move || value * value);
    }

    let mut count = 0;
    while let Some(result) = set.join_next().await {
        let _value = result.unwrap();
        count += 1;
    }
    assert_eq!(count, 3);
}
```

Remember that blocking tasks have different cancellation behavior from ordinary async tasks: once a `spawn_blocking` closure has started running, aborting its handle generally cannot stop the closure. Limit large CPU-bound workloads separately rather than assuming `JoinSet` supplies a CPU scheduler.

## Drop Aborts Remaining Tasks

```rust
use tokio::task::JoinSet;

async fn run_scope() {
    let mut set = JoinSet::new();
    set.spawn(std::future::pending::<()>());
    // `set` drops here, aborting the task still registered in it.
}

#[tokio::main]
async fn main() {
    run_scope().await;
}
```

This makes accidental loss of the set different from losing a standalone `JoinHandle`: dropping a `JoinHandle` detaches its task, while dropping a `JoinSet` aborts tasks that remain registered.

## JoinSet Versus a `Vec<JoinHandle<T>>`

Prefer `JoinSet` when you need dynamic insertion, completion-order processing, or set-wide lifecycle operations. A `Vec<JoinHandle<T>>` is still perfectly reasonable when the task collection is fixed and joining in a chosen order is simple and intentional.

Do not justify `JoinSet` with unsupported blanket performance claims. Choose it for the lifecycle and result-order semantics.

## Practical Guidance

- Drain `JoinError`s when failures or abort completion matter.
- Use `abort_all()` plus joining when you want to observe task termination.
- Use `shutdown()` only when immediate abort-and-drain is the desired operation.
- Use `detach_all()` only when tasks intentionally should continue untracked.
- For graceful shutdown, signal cooperatively before applying hard abortion.
- Remember that dropping the set aborts registered tasks.

## See Also

- [async-cancellation-token](./async-cancellation-token.md) — Cooperative cancellation
- [async-select-racing](./async-select-racing.md) — Racing lifecycle events
- [async-join-parallel](./async-join-parallel.md) — Concurrent futures without dynamic task tracking
