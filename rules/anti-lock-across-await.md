# anti-lock-across-await

> Avoid holding blocking lock guards across `.await`; async mutex guards may cross `.await` when resource serialization requires it

## Why It Matters

The slogan "never hold a lock across await" is too broad.

Holding a **blocking** `std::sync::Mutex`/`RwLock` guard across `.await` can block an executor worker thread and create deadlock or starvation hazards. An **async-aware** mutex such as `tokio::sync::Mutex` is specifically designed so its guard can be held across `.await`, though doing so serializes other tasks for the duration.

## Bad: Blocking Lock Across Await

```rust
use std::sync::Mutex;

async fn update(state: &Mutex<State>) {
    let mut state = state.lock().unwrap();
    let value = fetch().await;
    state.value = value;
}
```

Prefer doing async work outside the blocking critical section.

## Good for Ordinary Shared Data

```rust
use tokio::sync::Mutex;

struct State {
    value: u64,
}

async fn fetch() -> u64 {
    42
}

async fn update(state: &Mutex<State>) {
    let value = fetch().await;
    state.lock().await.value = value;
}
```

## Also Good: Intentional Async Serialization

```rust
use tokio::sync::Mutex;

async fn transact(conn: &Mutex<Connection>, request: Request) -> Response {
    let mut conn = conn.lock().await;
    conn.write(request).await;
    conn.read_response().await
}
```

If another task must not interleave protocol operations between the write and read, holding the async mutex across both awaits is the invariant, not an anti-pattern.

## Key Points

- Blocking lock + `.await` is a strong warning sign.
- Tokio's async mutex is explicitly intended to permit guards across `.await`.
- For plain shared data, keep async lock critical sections short where practical.
- For stateful resources, preserve required serialization even if it spans awaited operations.
- Message passing to a dedicated owner task can be a good alternative for complex resource protocols.

## See Also

- [async-no-lock-await](./async-no-lock-await.md) — canonical async-lock guidance
- [async-clone-before-await](./async-clone-before-await.md) — extract data before awaiting when appropriate
