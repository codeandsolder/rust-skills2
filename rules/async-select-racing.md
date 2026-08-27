# async-select-racing

> Use `tokio::select!` to wait on several async events, while reasoning explicitly about cancellation of the losing futures

## Why It Matters

`tokio::select!` polls several futures on the current task and runs the handler for the branch that becomes selected. The other branch futures are dropped when the `select!` expression finishes.

That makes cancellation semantics part of correctness. Dropping a future does not roll back work it already performed, and some operations are not cancellation safe when repeatedly recreated in a loop. Use `select!` when racing is the intended control flow, not as a generic replacement for sequential error handling.

## Good: Operation Versus Timeout

```rust
use std::time::Duration;

async fn fetch_data() -> u32 {
    tokio::time::sleep(Duration::from_millis(5)).await;
    42
}

#[tokio::main]
async fn main() {
    let result = tokio::select! {
        value = fetch_data() => Ok(value),
        _ = tokio::time::sleep(Duration::from_secs(1)) => Err("timeout"),
    };

    assert_eq!(result, Ok(42));
}
```

For a simple operation/deadline pair, `tokio::time::timeout` may communicate the intent more directly. `select!` becomes especially useful when there are several independent events or branch-specific behaviors.

## Losing Futures Are Dropped

```rust
use std::future::pending;

#[tokio::main]
async fn main() {
    let winner = tokio::select! {
        value = async { 7_u32 } => value,
        _ = pending::<()>() => 0,
    };

    assert_eq!(winner, 7);
}
```

The pending future is dropped after the other branch wins. Do not describe this as “the future keeps running until its next `.await`.” The future object is dropped; separately spawned tasks, OS operations, or external side effects may have their own lifetime semantics.

## Cancellation Safety Matters Most in Loops

Tokio defines a future as cancellation safe for this use when dropping it and recreating it does not lose progress that the caller relies on. Several receive-style operations are documented cancellation safe, including `mpsc::Receiver::recv`, `watch::Receiver::changed`, and `TcpListener::accept`. Others, such as `AsyncReadExt::read_exact` and queued synchronization acquisitions like `Mutex::lock`, are not cancellation safe in this sense.

```rust
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

async fn event_loop(
    mut rx: mpsc::Receiver<u32>,
    shutdown: CancellationToken,
) -> Vec<u32> {
    let mut values = Vec::new();

    loop {
        tokio::select! {
            _ = shutdown.cancelled() => break,
            value = rx.recv() => {
                match value {
                    Some(value) => values.push(value),
                    None => break,
                }
            }
        }
    }

    values
}

#[tokio::main]
async fn main() {
    let (_tx, rx) = mpsc::channel(4);
    let shutdown = CancellationToken::new();
    shutdown.cancel();
    assert!(event_loop(rx, shutdown).await.is_empty());
}
```

`recv()` and `CancellationToken::cancelled()` are documented cancellation safe, so restarting this `select!` loop does not lose a received message merely because the other branch won a previous iteration.

## Cancellation-Safe Does Not Mean “Always Prefer Cancellation”

A future can be non-cancellation-safe yet still be acceptable to cancel during process shutdown if abandoning its partial progress is intentional. Conversely, a technically cancellation-safe operation can still have application-level side effects you care about.

Ask what state is preserved or discarded when the losing future is dropped.

## Branch Preconditions and `else`

```rust
#[tokio::main]
async fn main() {
    let enabled = false;

    tokio::select! {
        _ = std::future::pending::<()>(), if enabled => {
            unreachable!();
        }
        else => {
            println!("all branches are disabled");
        }
    }
}
```

The `else` branch runs when every normal branch is disabled, for example because its `if` precondition is false or a branch pattern does not match. It does **not** mean “none of the enabled futures is ready yet”; in that case `select!` waits.

## Fairness and `biased;`

By default, Tokio varies the first branch it checks to provide fairness when multiple branches are ready. With `biased;`, branches are polled in source order and fairness becomes the caller's responsibility.

```rust
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let (_high_tx, mut high_rx) = mpsc::channel::<u32>(1);
    let (_low_tx, mut low_rx) = mpsc::channel::<u32>(1);

    tokio::select! {
        biased;
        value = high_rx.recv() => println!("high: {value:?}"),
        value = low_rx.recv() => println!("low: {value:?}"),
    }
}
```

If a high-volume branch is continuously ready in biased mode, placing a shutdown branch later can starve shutdown. Use biased ordering only when deterministic priority is intentional and reviewed.

## Dynamic Sets: Use a Stream/Future Collection

`select!` has a fixed set of branches in the macro invocation. For a dynamic number of same-shaped futures, use a collection designed for completion-order polling, such as `FuturesUnordered`:

```rust
use futures::stream::{FuturesUnordered, StreamExt};
use std::time::Duration;

async fn request(value: u32, delay_ms: u64) -> u32 {
    tokio::time::sleep(Duration::from_millis(delay_ms)).await;
    value
}

#[tokio::main]
async fn main() {
    let mut pending = FuturesUnordered::new();
    pending.push(request(1, 20));
    pending.push(request(2, 5));
    pending.push(request(3, 10));

    let fastest = pending.next().await.unwrap();
    assert_eq!(fastest, 2);

    // Dropping `pending` drops the remaining futures.
}
```

`futures::future::select_all` is another option, but it requires its futures to satisfy `Unpin`; directly collected async-function futures often do not. Do not recommend it without accounting for that bound.

## Pin a Reused Future When Necessary

Sometimes a future must keep its progress across loop iterations rather than being recreated each time. Create it outside the loop and pin it before selecting on `&mut` references to it. This is especially important for stateful operations whose cancellation behavior does not permit restart.

Do not mechanically pin every branch; use this pattern when the future's state must outlive one `select!` invocation.

## Practical Guidance

- Treat the losing branch as being dropped when another branch wins.
- Check cancellation-safety documentation for operations used in repeated `select!` loops.
- Use `biased;` only when source-order priority is intentional.
- Use `else` for disabled branches, not as a readiness timeout.
- Prefer `timeout()` for a simple deadline when it makes the code clearer.
- Use `FuturesUnordered`, `JoinSet`, or another dynamic collection instead of trying to generate dynamic `select!` branches.

## See Also

- [async-cancellation-token](./async-cancellation-token.md) — Cooperative cancellation signals
- [async-joinset-structured](./async-joinset-structured.md) — Dynamic spawned tasks
- [async-join-parallel](./async-join-parallel.md) — Waiting for all concurrent work
- [async-bounded-channel](./async-bounded-channel.md) — Channel operations in `select!`
