# async-cancellation-token

> Use `CancellationToken` when tasks need explicit cooperative cancellation

## Why It Matters

Dropping a Tokio `JoinHandle` detaches the task; it does not stop it. `tokio_util::sync::CancellationToken` provides an asynchronously awaitable cancellation signal that can be cloned or arranged into parent/child relationships.

A cancellation token is **cooperative**. Calling `cancel()` marks the token (and its descendants) cancelled and wakes waiters, but the application still decides where cancellation is observed and what cleanup runs. If code is executing a future that never observes the token, cancellation does not forcibly stop that future.

## Good: Cooperatively Stop a Worker

```rust
use tokio_util::sync::CancellationToken;

async fn worker(token: CancellationToken) {
    loop {
        tokio::select! {
            _ = token.cancelled() => break,
            _ = tokio::time::sleep(std::time::Duration::from_millis(10)) => {
                // Do one bounded unit of work.
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let token = CancellationToken::new();
    let handle = tokio::spawn(worker(token.clone()));

    token.cancel();
    handle.await.unwrap();
}
```

The losing `select!` branch is dropped. Any operation raced against cancellation therefore needs the cancellation behavior appropriate for the application; see [async-select-racing](./async-select-racing.md).

## Clone Versus Child Token

A clone and a child have different cancellation topology:

```rust
use tokio_util::sync::CancellationToken;

fn main() {
    let root = CancellationToken::new();
    let clone = root.clone();
    let child = root.child_token();

    child.cancel();
    assert!(child.is_cancelled());
    assert!(!root.is_cancelled());

    clone.cancel();
    assert!(root.is_cancelled());
}
```

Clones refer to the same cancellation state: cancelling any clone cancels them all. A child is cancelled when its parent is cancelled, but cancelling the child does not cancel the parent.

Use a child when a subsystem needs a narrower cancellation scope. Use a clone when all holders should represent the same cancellation domain.

**Dropping a parent token does not cancel its children.** Cancellation is triggered by `cancel()` (or a drop guard), not merely by lexical scope exit.

## CancellationToken API

```rust
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() {
    let token = CancellationToken::new();
    let waiter = token.clone();

    let task = tokio::spawn(async move {
        waiter.cancelled().await;
    });

    assert!(!token.is_cancelled());
    token.cancel();
    assert!(token.is_cancelled());
    task.await.unwrap();
}
```

Important operations:

- `cancel()` — request cancellation for this token and its child tokens;
- `is_cancelled()` — synchronous state check;
- `cancelled()` / `cancelled_owned()` — await cancellation;
- `child_token()` — create a one-way child cancellation relationship;
- `drop_guard()` / `drop_guard_ref()` — cancel on guard drop unless disarmed;
- `run_until_cancelled()` — race a supplied future against cancellation and drop that future if cancellation wins.

The `cancelled()` future itself is cancellation safe. `run_until_cancelled(fut)` is only cancellation safe if `fut` is cancellation safe.

## Hierarchical Cancellation

```rust
use tokio_util::sync::CancellationToken;

async fn subsystem(token: CancellationToken) {
    token.cancelled().await;
}

#[tokio::main]
async fn main() {
    let application = CancellationToken::new();
    let database = application.child_token();
    let cache = application.child_token();

    let db_task = tokio::spawn(subsystem(database.clone()));
    let cache_task = tokio::spawn(subsystem(cache));

    // Shut down only the database subtree.
    database.cancel();
    db_task.await.unwrap();
    assert!(!application.is_cancelled());

    // Later, application shutdown reaches remaining descendants.
    application.cancel();
    cache_task.await.unwrap();
}
```

Parent-to-child propagation is useful for structured subsystems, but it does not by itself join tasks or wait for cleanup. Track task lifetimes separately, for example with `JoinSet`.

## Graceful Shutdown: Signal, Then Join

```rust
use std::time::Duration;
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

async fn worker(token: CancellationToken) {
    token.cancelled().await;
    // Perform bounded synchronous/async cleanup here.
}

#[tokio::main]
async fn main() {
    let shutdown = CancellationToken::new();
    let mut tasks = JoinSet::new();

    for _ in 0..4 {
        tasks.spawn(worker(shutdown.clone()));
    }

    shutdown.cancel();

    let finished_gracefully = tokio::time::timeout(Duration::from_secs(1), async {
        while tasks.join_next().await.is_some() {}
    })
    .await
    .is_ok();

    if !finished_gracefully {
        tasks.abort_all();
        while tasks.join_next().await.is_some() {}
    }
}
```

This separates two different mechanisms:

1. the token asks tasks to finish cooperatively;
2. the task set observes completion and can apply a hard abort if a deadline expires.

`JoinSet::shutdown()` is **not** the graceful-wait phase: it aborts every task and then waits for abortion to finish.

## Drop Guards

```rust
use tokio_util::sync::CancellationToken;

fn main() {
    let token = CancellationToken::new();
    {
        let _guard = token.drop_guard_ref();
        assert!(!token.is_cancelled());
    }
    assert!(token.is_cancelled());
}
```

A drop guard is useful when leaving a scope should explicitly request cancellation. The owned `drop_guard()` consumes that token handle; `drop_guard_ref()` borrows it. Both can be disarmed when the scope completes normally.

## Practical Guidance

- Treat cancellation as a request, not forced task termination.
- Put cancellation points around operations where interruption has acceptable semantics.
- Distinguish shared clones from parent/child cancellation domains.
- Do not assume dropping a token requests cancellation.
- Pair cancellation signaling with explicit task joining when shutdown completion matters.
- Apply a timeout and `abort_all()` when graceful cleanup must have a hard deadline.

## See Also

- [async-joinset-structured](./async-joinset-structured.md) — Tracking and joining spawned tasks
- [async-select-racing](./async-select-racing.md) — Cancellation safety when racing futures
- [async-tokio-runtime](./async-tokio-runtime.md) — Runtime lifecycle
