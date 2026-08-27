# async-mpsc-queue

> Use `tokio::sync::mpsc` when an async task needs a single-consumer message queue with Tokio-aware waiting or backpressure

## Why It Matters

`tokio::sync::mpsc` is a multi-producer, single-consumer channel designed to integrate with async tasks. Its bounded form provides async backpressure: `Sender::send(...).await` waits for capacity instead of blocking the executor thread.

Do not turn this into “all channels in async code must be Tokio channels.” A synchronous channel can be appropriate at a sync/async boundary, and Tokio also has an unbounded channel whose `send` is synchronous. Choose based on where waiting happens, whether capacity must be bounded, and which side owns the runtime context.

## Bad: Blocking Receive on an Async Worker Thread

```rust
use std::sync::mpsc;

async fn bad_receive() {
    let (_tx, rx) = mpsc::channel::<String>();

    // `recv()` blocks the OS thread. If called directly from an async task,
    // it can prevent unrelated futures on that runtime worker from running.
    let _message = rx.recv().unwrap();
}

fn main() {}
```

The problem is the blocking operation inside async execution, not the mere existence of `std::sync::mpsc`.

## Good: Bounded Tokio MPSC

```rust
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = mpsc::channel::<String>(8);

    let producer = tokio::spawn(async move {
        tx.send("hello".to_owned()).await.unwrap();
    });

    assert_eq!(rx.recv().await.as_deref(), Some("hello"));
    producer.await.unwrap();
}
```

When the bounded channel is full, `send().await` yields until capacity becomes available or the channel closes.

## Multiple Producers, One Consumer

```rust
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = mpsc::channel::<u32>(8);

    let tx2 = tx.clone();
    let a = tokio::spawn(async move {
        tx.send(1).await.unwrap();
    });
    let b = tokio::spawn(async move {
        tx2.send(2).await.unwrap();
    });

    a.await.unwrap();
    b.await.unwrap();

    let mut values = vec![rx.recv().await.unwrap(), rx.recv().await.unwrap()];
    values.sort_unstable();
    assert_eq!(values, vec![1, 2]);
}
```

A receiver observes channel closure after all strong senders are dropped (or after the receiver is explicitly closed and the buffered messages are drained).

## Request/Response with `oneshot`

```rust
use tokio::sync::{mpsc, oneshot};

enum Command {
    Double {
        value: u32,
        reply: oneshot::Sender<u32>,
    },
}

async fn actor(mut rx: mpsc::Receiver<Command>) {
    while let Some(command) = rx.recv().await {
        match command {
            Command::Double { value, reply } => {
                let _ = reply.send(value * 2);
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let (tx, rx) = mpsc::channel(8);
    let task = tokio::spawn(actor(rx));

    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Command::Double {
        value: 21,
        reply: reply_tx,
    })
    .await
    .unwrap();

    assert_eq!(reply_rx.await.unwrap(), 42);
    drop(tx);
    task.await.unwrap();
}
```

This is a useful actor-style pattern when one task should own mutable state and callers need individual replies.

## Graceful Receiver Shutdown: Close, Then Drain

```rust
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

async fn consume(mut rx: mpsc::Receiver<u32>, shutdown: CancellationToken) -> Vec<u32> {
    let mut processed = Vec::new();

    loop {
        tokio::select! {
            _ = shutdown.cancelled() => {
                // Prevent future sends, then drain values already reserved/buffered.
                rx.close();
                while let Some(value) = rx.recv().await {
                    processed.push(value);
                }
                break;
            }
            value = rx.recv() => {
                match value {
                    Some(value) => processed.push(value),
                    None => break,
                }
            }
        }
    }

    processed
}

#[tokio::main]
async fn main() {
    let (tx, rx) = mpsc::channel(4);
    let shutdown = CancellationToken::new();
    tx.send(1).await.unwrap();
    shutdown.cancel();

    let values = consume(rx, shutdown).await;
    assert_eq!(values, vec![1]);
}
```

`Receiver::close()` prevents additional sends while still allowing buffered/reserved values to be received. A loop of `try_recv()` alone only drains what happens to be available at that instant and does not establish the same producer boundary.

## Reserve Capacity Before Expensive Construction

```rust
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = mpsc::channel(1);

    let permit = tx.reserve().await.unwrap();
    let message = String::from("constructed after capacity was reserved");
    permit.send(message);

    assert_eq!(rx.recv().await.as_deref(), Some("constructed after capacity was reserved"));
}
```

`reserve()` is useful when constructing a message is expensive and should happen only after bounded-channel capacity has been obtained. The permit represents reserved capacity; sending through it is synchronous.

## `WeakSender` Does Not Keep the Channel Alive

```rust
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = mpsc::channel::<u32>(4);
    let weak = tx.downgrade();

    assert!(weak.upgrade().is_some());
    drop(tx);

    assert!(weak.upgrade().is_none());
    assert_eq!(rx.recv().await, None);
}
```

Use a weak sender for references that should not extend the producer lifetime of the channel.

## `PollSender` Is a `Sink` Adapter

`tokio_util::sync::PollSender` wraps a Tokio `mpsc::Sender` with polling methods and implements `futures::Sink<T>`. Use the `Sink` protocol (`poll_ready` before `start_send`) or higher-level `SinkExt` helpers rather than calling `start_send` as if it were an ordinary unpinned method.

```rust
use futures::SinkExt;
use tokio::sync::mpsc;
use tokio_util::sync::PollSender;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = mpsc::channel::<u32>(4);
    let mut sink = PollSender::new(tx);

    sink.send(42).await.unwrap();
    drop(sink);

    assert_eq!(rx.recv().await, Some(42));
}
```

Use `PollSender` when an API specifically expects a `Sink`/poll-based sender. Ordinary Tokio code should usually call `mpsc::Sender::send().await` directly.

## Bounded Versus Unbounded

A bounded queue makes overload visible by applying backpressure. An unbounded queue avoids waiting for capacity but can grow until memory pressure becomes the failure mode. Prefer bounded capacity when the producer can reasonably slow down or shed work, and size it from workload behavior rather than a magic constant.

## Practical Guidance

- Do not call blocking receive APIs directly on async runtime workers.
- Prefer bounded `mpsc` when queue growth must be controlled.
- Drop/close senders deliberately so consumers can observe shutdown.
- Use `Receiver::close()` followed by `recv().await` to close producer admission and drain queued work.
- Use `reserve()` when capacity should be secured before expensive message creation.
- Reach for `PollSender` only when integrating with `Sink`/poll-based APIs.

## See Also

- [async-bounded-channel](./async-bounded-channel.md) — Backpressure and queue capacity
- [async-oneshot-response](./async-oneshot-response.md) — Request/response channels
- [async-broadcast-pubsub](./async-broadcast-pubsub.md) — Multiple receivers
- [async-cancellation-token](./async-cancellation-token.md) — Cooperative shutdown
