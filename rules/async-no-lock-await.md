# async-no-lock-await

> Keep blocking lock guards out of awaited sections; use an async mutex when exclusive access itself must span `.await`.

## Why It Matters

The useful rule is not "never hold any lock across `.await`." Rust async code commonly needs both short in-memory critical sections and serialized access to stateful async resources.

Two questions matter:

1. **Does acquiring/holding this lock block an OS thread?**
2. **Must exclusive ownership continue across the awaited operation to preserve an invariant?**

`std::sync::Mutex` is a blocking mutex. It is often the right choice for short data-only critical sections, but its guard should not live across `.await`. `tokio::sync::Mutex` waits asynchronously and its guard is designed to cross `.await`; use that extra capability when the protected resource actually needs it.

## Bad: Blocking Mutex Guard Across Await

<!-- rust-check: compile_fail; reason=std::sync::MutexGuard is !Send and remains live across await in a tokio::spawn future -->
```rust
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    value: u64,
}

fn spawn_bad(state: Arc<Mutex<State>>) {
    tokio::spawn(async move {
        let mut guard = state.lock().unwrap();
        guard.value += 1;

        tokio::task::yield_now().await;

        guard.value += 1;
    });
}
```

`tokio::spawn` requires a `Send + 'static` future, and `std::sync::MutexGuard` is `!Send`. The guard crossing the await therefore makes this spawned future invalid.

Even where the compiler permits a blocking guard in a non-`Send` local future, suspending while holding it can still deadlock or block executor progress. Do not treat the `Send` error as the only hazard.

## Good: Await First, Then Lock Ordinary Data Briefly

<!-- rust-check: compile -->
```rust
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    value: u64,
}

async fn fetch_from_network() -> u64 {
    tokio::task::yield_now().await;
    42
}

fn spawn_update(state: Arc<Mutex<State>>) {
    tokio::spawn(async move {
        let data = fetch_from_network().await;

        // Standard mutex is fine here: this critical section contains no await.
        state.lock().unwrap().value = data;
    });
}
```

For ordinary shared data, do not pay for an async mutex merely because the caller is async. Keep the blocking section short and never suspend while owning its guard.

## Good: Extract What You Need, Release, Await, Then Update

<!-- rust-check: compile -->
```rust
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct State {
    id: String,
    value: u64,
}

async fn fetch_by_id(id: String) -> u64 {
    tokio::task::yield_now().await;
    id.len() as u64
}

async fn update_by_id(state: Arc<Mutex<State>>) {
    let id = {
        let guard = state.lock().unwrap();
        guard.id.clone()
    }; // blocking guard dropped here

    let data = fetch_by_id(id).await;

    state.lock().unwrap().value = data;
}
```

This pattern is useful when the async operation only needs a snapshot/key rather than exclusive ownership of the protected object. The clone is justified by snapshot ownership and lock release, not by `.await` itself.

## Good: Async Mutex Across Await When the Resource Must Stay Exclusive

Some resources are stateful protocols: socket wrappers, device sessions, transaction-like handles, or anything where another task must not interleave operations halfway through a logical exchange.

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
        Response(self.pending.take().expect("request is pending"))
    }
}

async fn send_request(
    conn: Arc<Mutex<Connection>>,
    request: Request,
) -> Response {
    let mut conn = conn.lock().await;

    // Intentional serialization across both awaits.
    conn.write_request(request).await;
    conn.read_response().await
}
```

The Tokio mutex is doing real protocol work here. Releasing it after the write would allow another task to interleave and consume/mutate connection state between the paired operations.

## Async Mutex Is Not a Universal Upgrade

Tokio's mutex is more expensive because waiting is asynchronous and the guard can survive suspension. Its main value is precisely that capability.

For plain data:

- prefer `std::sync::Mutex` or another suitable blocking/data lock when critical sections are short and never await;
- avoid high contention or expensive work while the guard is held;
- if a lock regularly spans asynchronous operations, ask whether the protected thing is actually a stateful async resource.

For a stateful async resource:

- `tokio::sync::Mutex` can be the simplest correct design;
- holding the guard across awaits is acceptable when required by the invariant;
- measure contention if many tasks serialize on a long operation.

## Message-Passing Alternative

A dedicated task can own the resource and serialize commands without sharing a mutex at all.

<!-- rust-check: compile -->
```rust
use tokio::sync::{mpsc, oneshot};

#[derive(Default)]
struct Resource {
    value: u64,
}

enum Command {
    Increment {
        by: u64,
        reply: oneshot::Sender<u64>,
    },
}

async fn resource_task(
    mut resource: Resource,
    mut rx: mpsc::Receiver<Command>,
) {
    while let Some(command) = rx.recv().await {
        match command {
            Command::Increment { by, reply } => {
                resource.value += by;
                let _ = reply.send(resource.value);
            }
        }
    }
}
```

This is attractive when one component naturally owns a resource or when sequencing rules are richer than mutual exclusion. It also gives the queue an explicit place to implement bounded backpressure and shutdown policy.

## Blocking Work Is a Separate Concern

Changing `std::sync::Mutex` to `tokio::sync::Mutex` does not make CPU-heavy or blocking I/O inside the critical section asynchronous. If the protected operation itself blocks a thread for a meaningful duration, use an appropriate blocking thread/pool strategy such as `spawn_blocking`, or redesign ownership.

## Decision Guide

| Situation | Typical choice |
|---|---|
| Short critical section over in-memory data, no await | blocking/data mutex |
| Need data only to start an async operation | copy/clone needed fields, release lock, await |
| Must keep one async resource exclusively owned across awaits | async mutex |
| Complex serialized protocol / natural single owner | owner task + channels |
| Long blocking operation | move blocking work off executor workers |

## Key Points

- A blocking mutex guard crossing `.await` is a strong bug smell and is often rejected when a `Send` future is required.
- A Tokio mutex guard is explicitly designed to cross `.await`.
- Holding an async guard across `.await` is not automatically wrong; unnecessary serialization is the tradeoff.
- Use a standard mutex for ordinary data when the guard stays entirely in synchronous sections.
- Pick mutexes/message passing from ownership and sequencing semantics, not slogans.

## See Also

- [anti-lock-across-await](./anti-lock-across-await.md) - Concise anti-pattern reference
- [async-clone-before-await](./async-clone-before-await.md) - Ownership and snapshots across await
- [async-mpsc-queue](./async-mpsc-queue.md) - Owner-task and queue patterns
- [async-spawn-blocking](./async-spawn-blocking.md) - Blocking work in async applications
