# async-join-parallel

> Use `join!` / `try_join!` for a fixed set of independent futures; they run concurrently on one task, not in parallel by themselves

## Why It Matters

Awaiting independent I/O operations one after another serializes their waiting time. Tokio's `join!` and `try_join!` poll several futures as part of one parent task, allowing their waits to overlap without spawning separate tasks or allocating a collection.

That is **concurrency**, not automatic parallel execution: the joined futures are multiplexed on the current task. If one branch performs blocking work or a long CPU loop without yielding, it prevents the other branches from progressing too.

## Bad: Unnecessarily Sequential Independent Work

```rust
async fn operation_a() -> u32 {
    tokio::task::yield_now().await;
    10
}

async fn operation_b() -> u32 {
    tokio::task::yield_now().await;
    20
}

async fn sequential() -> (u32, u32) {
    let a = operation_a().await;
    let b = operation_b().await;
    (a, b)
}
```

When `b` does not depend on `a`, this waits for the first future before even beginning to poll the second.

## Good: Join Independent Futures

```rust
async fn operation_a() -> u32 {
    tokio::task::yield_now().await;
    10
}

async fn operation_b() -> u32 {
    tokio::task::yield_now().await;
    20
}

async fn concurrent() -> (u32, u32) {
    tokio::join!(operation_a(), operation_b())
}
```

The futures are stored inline in the generated `join!` future and are polled until both complete.

## Fallible Operations

```rust
async fn load_a() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(10)
}

async fn load_b() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(20)
}

async fn load_both() -> Result<(u32, u32), &'static str> {
    tokio::try_join!(load_a(), load_b())
}
```

`try_join!` returns when all branches succeed or when one branch returns `Err`. See the dedicated rule for the cancellation consequences of that early error.

## Polling Fairness

Tokio `join!` does **not** always poll branches in declaration order. By default, the generated future rotates which branch is polled first whenever it wakes. `try_join!` behaves the same way.

Use the macro's own `biased;` mode only when fixed top-to-bottom polling order is intentional:

```rust
async fn first() {
    tokio::task::yield_now().await;
}

async fn second() {
    tokio::task::yield_now().await;
}

async fn ordered_polling() {
    tokio::join!(
        biased;
        first(),
        second(),
    );
}
```

With `biased;`, fairness becomes the caller's responsibility. A branch that is frequently ready and expensive per poll can delay branches listed later.

## Dynamic Collections

For a runtime-sized set of futures, a tuple macro is the wrong shape. `FuturesUnordered`, buffered streams, `JoinSet`, or `join_all` may fit depending on whether you need bounded concurrency, task spawning, completion-order processing, or ordered collection.

<!-- rust-check: compile -->
```rust
use futures::stream::{self, StreamExt};

async fn fetch_user(id: u64) -> u64 {
    tokio::task::yield_now().await;
    id
}

async fn fetch_users(ids: Vec<u64>) -> Vec<u64> {
    stream::iter(ids)
        .map(fetch_user)
        .buffer_unordered(16)
        .collect::<Vec<_>>()
        .await
}
```

`buffer_unordered(16)` bounds the number of in-flight futures from this stream at sixteen. Choose the bound from resource limits and measurements rather than treating sixteen as universal.

## Concurrency Is Not CPU Parallelism

`join!` cannot make CPU-heavy synchronous work run on two cores because both branches are polled by the same task. `tokio::spawn` can place independent `Send + 'static` async tasks on different runtime workers on a multi-thread runtime, but sustained CPU-bound workloads are usually better isolated with a bounded `spawn_blocking` workload or a CPU-oriented pool such as Rayon.

Do not turn compute functions into fake async functions merely to put them inside `join!`.

## Dependent Work Should Stay Sequential

```rust
async fn create_id() -> u64 {
    7
}

async fn populate(id: u64) -> usize {
    id as usize
}

async fn create_and_populate() -> usize {
    let id = create_id().await;
    populate(id).await
}
```

The second operation genuinely depends on the first result, so joining them would not express the dependency.

## Choosing the Primitive

| Need | Typical primitive |
|------|-------------------|
| Fixed independent futures, keep all outputs | `join!` |
| Fixed fallible futures, fail on first error | `try_join!` |
| First branch to complete | `select!` |
| Dynamic spawned task set | `JoinSet` |
| Dynamic futures with bounded concurrency | buffered stream / `FuturesUnordered` + admission bound |
| Sustained CPU parallelism | CPU-oriented pool / explicitly bounded blocking work |

## See Also

- [async-try-join](./async-try-join.md) — fallible joined futures
- [async-select-racing](./async-select-racing.md) — first-to-complete semantics
- [async-joinset-structured](./async-joinset-structured.md) — dynamic task sets
- [async-spawn-blocking](./async-spawn-blocking.md) — blocking and CPU work
