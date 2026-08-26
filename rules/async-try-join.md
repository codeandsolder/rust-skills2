# async-try-join

> Use `try_join!` for a fixed set of fallible futures that should run concurrently and stop when one returns an error

## Why It Matters

Tokio's `try_join!` polls several fallible futures concurrently on the **same parent task**. It returns their outputs when every branch succeeds, or returns the first observed error and drops the remaining branch futures.

That is fail-fast concurrency, not parallel execution. A branch that blocks the thread or performs long CPU work without yielding prevents the other joined branches from progressing.

## Bad: Independent Operations Run Sequentially

```rust
async fn fetch_a() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(1)
}

async fn fetch_b() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(2)
}

async fn sequential() -> Result<(u32, u32), &'static str> {
    let a = fetch_a().await?;
    let b = fetch_b().await?;
    Ok((a, b))
}
```

If `fetch_b` is independent of `fetch_a`, its waiting time need not be serialized behind `fetch_a`.

## Good

```rust
async fn fetch_a() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(1)
}

async fn fetch_b() -> Result<u32, &'static str> {
    tokio::task::yield_now().await;
    Ok(2)
}

async fn concurrent() -> Result<(u32, u32), &'static str> {
    tokio::try_join!(fetch_a(), fetch_b())
}
```

For a fixed number of branches, the futures are stored inline by the macro; no `Vec` of futures is required.

## Cancellation on Error

When one branch returns `Err`, `try_join!` returns and the other **unspawned branch futures are dropped**. They are no longer polled after that point. This is ordinary future cancellation by destruction, not “they keep running until their next `.await`.”

Already-issued external side effects may of course outlive a dropped future, and whether an async operation is safe to cancel depends on that operation's contract.

```rust
async fn step_a() -> Result<(), &'static str> {
    tokio::task::yield_now().await;
    Ok(())
}

async fn step_b() -> Result<(), &'static str> {
    Err("failed")
}

async fn run_steps() -> Result<(), &'static str> {
    tokio::try_join!(step_a(), step_b())?;
    Ok(())
}
```

Do not put required cleanup only after a cancellation point in a future that may be dropped. Use RAII for synchronous cleanup and explicit higher-level protocols when async cleanup must be guaranteed.

### Spawned Tasks Are Different

A `JoinHandle` is itself a future, but dropping a Tokio `JoinHandle` **detaches** the task rather than aborting it. Therefore `try_join!` over join handles does not imply that sibling tasks stop when one handle resolves to an error. Abort or otherwise own spawned tasks explicitly when cancellation of spawned work is required.

## Polling Fairness

By default, Tokio `try_join!` rotates which contained future is polled first whenever the generated future wakes. It does not choose a random branch each time.

The macro supports `biased;` directly:

```rust
async fn control() -> Result<(), &'static str> {
    Ok(())
}

async fn workload() -> Result<(), &'static str> {
    tokio::task::yield_now().await;
    Ok(())
}

async fn fixed_poll_order() -> Result<((), ()), &'static str> {
    tokio::try_join!(
        biased;
        control(),
        workload(),
    )
}
```

With biased mode, branches are always polled top-to-bottom and the caller is responsible for fairness. Put latency-sensitive control/shutdown work early if a later branch can consume substantial time per poll.

## Timeouts

`tokio::time::timeout` expects a future. Since `try_join!` is evaluated inside async control flow and produces its final `Result`, wrap the joined operation in an async block when applying one timeout to the whole group:

```rust
use std::time::Duration;

async fn fetch_a() -> Result<u32, &'static str> { Ok(1) }
async fn fetch_b() -> Result<u32, &'static str> { Ok(2) }

async fn with_timeout() -> Result<(u32, u32), &'static str> {
    match tokio::time::timeout(
        Duration::from_secs(1),
        async { tokio::try_join!(fetch_a(), fetch_b()) },
    )
    .await
    {
        Ok(result) => result,
        Err(_) => Err("timed out"),
    }
}
```

For per-operation timeouts, wrap each operation in a helper future that converts `Elapsed` into the common error type before passing those futures to `try_join!`.

## Different Error Types

All branches must be compatible with a common error type. Convert at the boundary:

<!-- rust-check: fragment; reason=application-specific error enum and fetch functions -->
```rust
let (user, config) = tokio::try_join!(
    fetch_user().map_err(AppError::from),
    fetch_config().map_err(AppError::from),
)?;
```

Depending on the future type, combinators such as `map_err` may require `TryFutureExt`; an explicit `async { fetch_user().await.map_err(AppError::from) }` wrapper avoids that trait dependency.

## Dynamic Collections

For a runtime-sized collection, use a dynamic primitive such as a buffered stream, `FuturesUnordered`, or spawned `JoinSet`, depending on ordering, task ownership, and cancellation needs. Bound concurrency when the collection can be large.

`futures::future::try_join_all` is useful when all futures should be driven concurrently and collected in input order, but it is not a backpressure mechanism for an arbitrarily large input.

## Choosing the Primitive

| Need | Primitive |
|------|-----------|
| Fixed infallible branches | `join!` |
| Fixed fallible branches, stop polling siblings on error | `try_join!` |
| First completion regardless of error | `select!` |
| Dynamic futures, completion-order processing | `FuturesUnordered` |
| Dynamic spawned tasks | `JoinSet` |

## See Also

- [async-join-parallel](./async-join-parallel.md) — joined futures and concurrency vs parallelism
- [async-select-racing](./async-select-racing.md) — first-to-complete semantics
- [async-joinset-structured](./async-joinset-structured.md) — spawned task ownership
- [err-question-mark](./err-question-mark.md) — error propagation

## References

- [Tokio `try_join!`](https://docs.rs/tokio/latest/tokio/macro.try_join.html)
- [Tokio `join!`](https://docs.rs/tokio/latest/tokio/macro.join.html)
