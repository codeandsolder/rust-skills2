# async-no-lock-await

> Avoid holding blocking mutex guards across `.await`; keep async-lock critical sections small, but hold an async mutex across `.await` when the protected resource invariant genuinely requires it.

## Why It Matters

A blanket "never hold a lock across `.await`" rule is wrong. The important distinction is between **blocking locks** such as `std::sync::Mutex` and **async-aware locks** such as `tokio::sync::Mutex`.

A blocking mutex guard held across `.await` can block an executor worker thread and may deadlock or starve unrelated tasks. Tokio's async mutex is specifically designed so its guard may be held across `.await`, but doing so keeps other tasks from accessing the protected resource for the entire asynchronous operation. That can be exactly the right behavior for a stateful I/O resource, or needless contention for ordinary in-memory data.

## Bad: Blocking Mutex Across Await

```rust
use std::sync::Mutex;

async fn bad_update(state: &Mutex<State>) {
    let mut guard = state.lock().unwrap();

    // BAD: a blocking mutex remains locked while this task is suspended.
    let data = fetch_from_network().await;
    guard.value = data;
}
```

For ordinary shared data, prefer doing asynchronous work before acquiring the lock:

```rust
use tokio::sync::Mutex;

async fn update(state: &Mutex<State>) {
    let data = fetch_from_network().await;

    let mut guard = state.lock().await;
    guard.value = data;
}
```

## Good: Extract, Await, Then Update

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use tokio::sync::Mutex;

async fn update_by_id(state: &Mutex<State>) {
    let id = {
        let guard = state.lock().await;
        guard.id.clone()
    };

    let data = fetch_by_id(id).await;

    state.lock().await.value = data;
}
```

This minimizes lock hold time when the asynchronous operation does not depend on exclusive ownership of the protected resource.

## Also Good: Async Mutex Across Await When Required

Some resources are inherently stateful. A connection, protocol session, transaction-like object, or device handle may require one task to retain exclusive access across several awaited operations.

```rust
use tokio::sync::Mutex;

async fn send_request(conn: &Mutex<Connection>, request: Request) -> Response {
    let mut conn = conn.lock().await;

    // Holding the Tokio mutex here is intentional: another task must not
    // interleave operations on this connection between write and read.
    conn.write_request(request).await;
    conn.read_response().await
}
```

Tokio's mutex guard is designed to be held across `.await`. The tradeoff is contention and the higher cost of an async mutex, not memory unsafety or an automatic deadlock.

## `std::sync::Mutex` vs `tokio::sync::Mutex`

- Use `std::sync::Mutex` (or another blocking mutex) for short, non-async critical sections when contention is low and the guard is never held across `.await`.
- Use `tokio::sync::Mutex` when the protected operation itself must cross `.await` points.
- For plain data, prefer restructuring code so asynchronous work happens outside the lock.
- For shared I/O resources, an async mutex or a dedicated owner task/message-passing design is often appropriate.

## Message-Passing Alternative

A dedicated task can own a stateful resource and serialize operations without exposing a mutex to callers:

```rust
async fn resource_task(mut resource: Resource, mut rx: mpsc::Receiver<Command>) {
    while let Some(command) = rx.recv().await {
        resource.handle(command).await;
    }
}
```

This is especially useful when operations have richer sequencing requirements than simple mutual exclusion.

## Key Points

- **Do not hold blocking mutex/RwLock guards across `.await`.**
- Tokio's async mutex is explicitly designed to permit holding its guard across `.await`.
- Even with an async mutex, minimize the critical section unless the resource invariant requires exclusivity across the awaited operation.
- Choose between locking and message passing based on resource ownership and sequencing, not an absolute slogan.

## See Also

- [async-spawn-blocking](async-spawn-blocking.md) - Move blocking operations off executor workers
- [async-clone-before-await](async-clone-before-await.md) - Clone or extract data before awaiting when appropriate
- [anti-lock-across-await](anti-lock-across-await.md) - Anti-pattern reference
