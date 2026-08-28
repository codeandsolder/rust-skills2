# anti-lock-across-await

> Do not hold blocking lock guards across `.await`; an async mutex may intentionally span `.await` when the protected resource must remain exclusively owned.

## Why It Matters

"Never hold a lock across `.await`" is too broad. The important distinction is the lock implementation and the invariant being protected.

A blocking lock such as `std::sync::Mutex` blocks the current OS thread while waiting. Its `MutexGuard` is also deliberately `!Send`, so a future that keeps that guard across an `.await` cannot be passed to `tokio::spawn`. Even on a local executor where `Send` is not required, holding a blocking guard across suspension can deadlock or stall an executor thread if another task later tries to acquire the same lock.

Tokio's async mutex has an asynchronously waiting `lock().await`, and its guard is designed to be held across `.await`. That costs more than a blocking mutex and serializes other tasks for the full guard lifetime, but it is the right tool when exclusive ownership of a stateful async resource genuinely must span several awaited operations.

## Bad: Blocking Guard Held Across Await

<!-- rust-check: compile_fail; reason=std::sync::MutexGuard is !Send and is held across await inside a future passed to tokio::spawn -->
```rust
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    value: u64,
}

fn spawn_bad_update(state: Arc<Mutex<State>>) {
    tokio::spawn(async move {
        let mut guard = state.lock().unwrap();
        guard.value += 1;

        tokio::task::yield_now().await;

        guard.value += 1;
    });
}
```

The compiler rejection here is useful, but it is not the whole reason to avoid the pattern. A non-`Send` local task can still create runtime blocking/deadlock hazards if it suspends while owning a blocking mutex guard.

## Good: Async Work First, Short Blocking Critical Section Afterward

For ordinary in-memory data, a standard mutex is often fine when the guard never crosses `.await`.

<!-- rust-check: compile -->
```rust
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    value: u64,
}

async fn fetch_value() -> u64 {
    tokio::task::yield_now().await;
    42
}

fn spawn_good_update(state: Arc<Mutex<State>>) {
    tokio::spawn(async move {
        let value = fetch_value().await;

        // No await while this blocking guard exists.
        state.lock().unwrap().value = value;
    });
}
```

Do not switch ordinary data to `tokio::sync::Mutex` merely because the surrounding function is async. Tokio itself recommends a blocking mutex for many data-only cases where the guard stays out of awaited sections.

## Also Good: Async Mutex Across Await When Serialization Is the Invariant

A connection or device session may require a write and its matching read to remain indivisible with respect to other tasks.

<!-- rust-check: compile -->
```rust
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Clone, Copy)]
struct Request(u64);

#[derive(Debug, PartialEq, Eq)]
struct Response(u64);

#[derive(Default)]
struct Connection {
    pending: Option<u64>,
}

impl Connection {
    async fn write_request(&mut self, request: Request) {
        tokio::task::yield_now().await;
        self.pending = Some(request.0);
    }

    async fn read_response(&mut self) -> Response {
        tokio::task::yield_now().await;
        Response(self.pending.take().expect("write precedes read"))
    }
}

async fn transact(conn: Arc<Mutex<Connection>>, request: Request) -> Response {
    let mut conn = conn.lock().await;
    conn.write_request(request).await;
    conn.read_response().await
}
```

Holding the Tokio guard here is intentional: releasing it between `write_request` and `read_response` would allow another task to interleave a request and violate the protocol.

## Ask What the Lock Protects

- **Plain shared data:** prefer a short critical section with no `.await` while a blocking guard exists.
- **Stateful async resource:** an async mutex may correctly protect a sequence that spans awaits.
- **Complex protocol ownership:** a dedicated owner task plus channels may make sequencing clearer than sharing a mutex.
- **Long CPU/blocking operation:** moving the operation to `spawn_blocking` may be more appropriate than changing mutex type.

The goal is not "zero locks across await". The goal is to avoid blocking executor threads and to preserve the resource's real serialization requirements.

## See Also

- [async-no-lock-await](./async-no-lock-await.md) — canonical async lock guidance
- [async-clone-before-await](./async-clone-before-await.md) — ownership and borrows across await
- [async-mpsc-queue](./async-mpsc-queue.md) — dedicated owner-task patterns
