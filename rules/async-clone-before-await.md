# async-clone-before-await

> Do not clone merely because an `.await` exists; clone or move ownership when a task/lifetime boundary actually requires ownership.

## Why It Matters

A reference may legally live across an `.await`. Whether the resulting future is `Send` depends on the referenced type: `&T` is `Send` when `T: Sync`. Borrowing data stored inside an owned `Arc<T>` therefore does **not** inherently make an async function non-`Send`.

Cloning is useful for a different reason: ownership. A spawned task usually must own everything it keeps because `tokio::spawn` requires a `Send + 'static` future. Cloning an `Arc` is a cheap way to give the task another owning handle; cloning the entire inner value is often unnecessary.

## Bad: Deep-Cloning Just Because an Await Follows

<!-- rust-check: compile -->
```rust
use std::sync::Arc;

#[derive(Debug)]
struct Data {
    items: Vec<u64>,
}

async fn pause() {
    tokio::task::yield_now().await;
}

async fn unnecessary_clone(data: Arc<Data>) -> u64 {
    // This duplicates the entire Vec even though `data` itself lives for the
    // whole future and its contents can be borrowed safely.
    let items = data.items.clone();
    pause().await;
    items.iter().sum()
}
```

The clone is not made correct merely by appearing before `.await`; it needs an ownership or snapshot-semantics reason.

## Good: Borrow Across Await When the Owner Lives Long Enough

<!-- rust-check: compile -->
```rust
use std::sync::Arc;

#[derive(Debug)]
struct Data {
    items: Vec<u64>,
}

async fn pause() {
    tokio::task::yield_now().await;
}

async fn borrow_across_await(data: Arc<Data>) -> u64 {
    let items: &[u64] = &data.items;
    pause().await;
    items.iter().sum()
}

fn assert_send<T: Send>(_: T) {}

fn proves_this_future_is_send() {
    let data = Arc::new(Data { items: vec![1, 2, 3] });
    assert_send(borrow_across_await(data));
}
```

`u64` is `Sync`, so `&[u64]` is `Send`. The future also owns the `Arc<Data>` that keeps the borrowed allocation alive.

The same pattern can fail for a genuinely non-`Sync` target. `Arc<T>` does not magically make a non-thread-safe `T` thread-safe.

## Spawned Tasks Need Owned `'static` State

`tokio::spawn` requires the spawned future and its output to be `Send + 'static`. If the caller wants to retain its `Arc`, clone the **Arc handle** before moving that handle into the task.

<!-- rust-check: compile -->
```rust
use std::sync::Arc;
use tokio::task::JoinHandle;

#[derive(Debug)]
struct Shared {
    values: Vec<u64>,
}

fn spawn_reader(shared: &Arc<Shared>) -> JoinHandle<usize> {
    let task_shared = Arc::clone(shared);

    tokio::spawn(async move {
        tokio::task::yield_now().await;
        task_shared.values.len()
    })
}
```

`Arc::clone` increments a reference count; it does not clone `Shared` or its `Vec`.

If ownership is being transferred permanently and the caller does not need the value afterward, move the existing `Arc` instead of cloning even the handle.

## Non-Send State Is the Real Send Problem

Holding `Rc<T>` across an await makes that future non-`Send`. A multi-thread-capable `tokio::spawn` therefore rejects it.

<!-- rust-check: compile_fail; reason=Rc is held across await, so the future passed to tokio::spawn is not Send -->
```rust
use std::rc::Rc;

async fn uses_rc() {
    let value = Rc::new(42_u64);
    tokio::task::yield_now().await;
    println!("{value}");
}

fn spawn_non_send() {
    tokio::spawn(uses_rc());
}
```

Options include:

- use thread-safe state such as `Arc<T>` when the data genuinely crosses threads,
- make the non-`Send` value stop living before the await if it is only needed synchronously,
- run deliberately non-`Send` futures on a suitable local executor such as Tokio `LocalSet` / `spawn_local`.

Do not convert `Rc` to `Arc` mechanically if the task is intentionally single-thread-local.

## Clone a Snapshot When Snapshot Semantics Are Desired

Sometimes cloning before an await is exactly right because the operation should use a stable snapshot independent of later shared-state changes.

<!-- rust-check: compile -->
```rust
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Default)]
struct State {
    label: String,
}

async fn snapshot_label(state: Arc<RwLock<State>>) -> String {
    let label = state.read().await.label.clone();

    // The lock is released, and `label` is an owned snapshot.
    tokio::task::yield_now().await;
    label
}
```

Here the clone both shortens the lock lifetime and defines which version of the data the rest of the operation sees.

## Prefer Scope Reduction to Unnecessary Copies

If only a derived value is needed after the await, compute that value before suspension rather than cloning a large structure.

<!-- rust-check: compile -->
```rust
use std::sync::Arc;

struct Data {
    items: Vec<u64>,
}

async fn sum_then_wait(data: Arc<Data>) -> u64 {
    let sum = data.items.iter().copied().sum::<u64>();
    tokio::task::yield_now().await;
    sum
}
```

## Decision Guide

| Situation | Typical choice |
|---|---|
| Owned `Arc<T>` lives for the whole future and borrowed `T` is `Sync` | Borrow across `.await` if convenient |
| Spawned task needs its own ownership while caller keeps state | `Arc::clone` before `async move` |
| Caller transfers ownership completely | Move the existing owner |
| Need a stable snapshot / release a lock | Clone only the required data |
| Value is needed only before `.await` | End its scope before `.await` |
| Intentionally non-`Send` task | Use a local executor rather than cloning blindly |

## See Also

- [async-no-lock-await](./async-no-lock-await.md) - Lock lifetime across await points
- [own-arc-shared](./own-arc-shared.md) - Arc ownership patterns
- [async-spawn-blocking](./async-spawn-blocking.md) - Keeping blocking work off async workers
