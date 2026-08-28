# async-bounded-channel

> Prefer bounded channels when backlog growth must be constrained; use unbounded channels only when an external invariant bounds the backlog.

## Why It Matters

`tokio::sync::mpsc::channel` has a fixed queue capacity. When that queue is full, `Sender::send(...).await` **asynchronously waits** for capacity instead of growing the queue. That is backpressure.

`mpsc::unbounded_channel` has no channel-level backpressure. `UnboundedSender::send` is synchronous and messages may be buffered arbitrarily while the receiver falls behind. System memory is therefore the practical bound, and an overloaded producer can drive the process to OOM.

Neither API promises that sends always succeed: bounded and unbounded sends fail when the receive half has been closed or dropped.

## Bad: Unbounded Backlog Without an External Bound

<!-- rust-check: compile -->
```rust
use tokio::sync::mpsc;

#[derive(Debug)]
struct Message(Vec<u8>);

fn enqueue_burst() {
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    // There is no queue capacity here. In a long-running producer loop,
    // `send` can keep allocating while the receiver falls behind.
    for _ in 0..1_000 {
        tx.send(Message(vec![0; 1024]))
            .expect("receiver is still alive");
    }

    while let Ok(message) = rx.try_recv() {
        let _ = message.0.len();
    }
}
```

The problem is not that an unbounded channel is always wrong. The problem is using one where producer rate or burst size is not otherwise bounded.

## Good: Bounded Queue With Backpressure

<!-- rust-check: compile -->
```rust
use tokio::sync::mpsc;

async fn bounded_pipeline() -> Result<(), mpsc::error::SendError<u64>> {
    let (tx, mut rx) = mpsc::channel::<u64>(8);

    tx.send(42).await?;
    assert_eq!(rx.recv().await, Some(42));

    Ok(())
}
```

If all eight slots are occupied, a later `send(...).await` waits until the receiver removes an item or the channel closes. Waiting here suspends the task; it does not block the executor thread.

A bounded queue limits the number of values stored **inside that queue**. It does not place a byte-accurate cap on the whole application: individual messages may own large allocations, and producers may retain other data outside the channel.

## Choose Capacity From the Workload

There is no universal correct capacity. Treat it as a resource and latency decision:

- enough room for the burst you intentionally want to absorb,
- small enough that overload becomes visible before memory and latency explode,
- measured under representative producer/consumer rates,
- revisited when message size or service time changes.

A capacity of `1` is useful when you want almost-immediate backpressure. A large capacity can improve burst tolerance but also allows a larger stale backlog.

## Decide What Full Means

Waiting is only one overload policy. Tokio also supports immediate refusal and application-level deadlines.

<!-- rust-check: compile -->
```rust
use tokio::sync::mpsc;
use tokio::time::{timeout, Duration};

fn try_without_waiting(tx: &mpsc::Sender<String>, message: String) {
    match tx.try_send(message) {
        Ok(()) => {}
        Err(mpsc::error::TrySendError::Full(message)) => {
            // Drop, retry elsewhere, or return overload to the caller.
            drop(message);
        }
        Err(mpsc::error::TrySendError::Closed(message)) => {
            // The consumer is gone; the value is returned to us.
            drop(message);
        }
    }
}

async fn send_with_deadline(
    tx: &mpsc::Sender<String>,
    message: String,
) -> Result<(), &'static str> {
    match timeout(Duration::from_millis(50), tx.send(message)).await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(_closed)) => Err("receiver closed"),
        Err(_elapsed) => Err("queue stayed full too long"),
    }
}
```

`try_send` is appropriate when overload is itself part of the API contract. A timeout is appropriate when waiting is acceptable only up to a deadline. Do not silently convert every full queue into message loss.

## Reserve Capacity Before Expensive Construction

When building a message is expensive, reserve queue capacity first.

<!-- rust-check: compile -->
```rust
use tokio::sync::mpsc;

async fn build_after_capacity(tx: &mpsc::Sender<Vec<u8>>) {
    if let Ok(permit) = tx.reserve().await {
        let payload = vec![0_u8; 64 * 1024];
        permit.send(payload);
    }
}
```

A permit reserves one slot. Once acquired, `Permit::send` consumes that reservation; the capacity is no longer racing another sender.

## One Receiver Means One Work-Queue Consumer

Tokio `mpsc` supports many senders but one `Receiver`. The receiver is not cloneable. If several workers should each process a different job, common designs include:

- one dispatcher that receives jobs and sends them to per-worker channels,
- a dedicated owner task that performs the work itself,
- a channel implementation whose semantics are explicitly multi-consumer.

Do **not** replace a work queue with `broadcast`: broadcast makes every active subscriber eligible to receive every message, which is fan-out rather than load distribution.

## Pick the Channel for the Delivery Semantics

| Need | Tokio primitive |
|---|---|
| Many producers, one queued consumer | bounded `mpsc` |
| One queued value / one response | `oneshot` |
| Every subscriber sees each retained event | `broadcast` |
| Receivers only need the newest state | `watch` |

The queue type should follow the delivery contract first; performance tuning comes after that.

## When Unbounded Can Be Reasonable

An unbounded channel can be appropriate when the backlog is bounded somewhere else, for example:

- the producer can emit only a small finite number of messages,
- a synchronous callback must hand work into async code and another resource already caps outstanding work,
- shutdown/control messages are inherently sparse.

State that invariant. "It has been fine so far" is not a bound.

## See Also

- [async-mpsc-queue](./async-mpsc-queue.md) - MPSC queue semantics and shutdown
- [async-oneshot-response](./async-oneshot-response.md) - Single-response channels
- [async-watch-latest](./async-watch-latest.md) - Latest-value state distribution
