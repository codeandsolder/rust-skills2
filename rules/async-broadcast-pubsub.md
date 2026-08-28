# async-broadcast-pubsub

> Use `tokio::sync::broadcast` for bounded fan-out where every active subscriber should observe each retained event.

## Why It Matters

Tokio `broadcast` is a multi-producer, multi-consumer channel. Each sent value is made available to every active receiver. That is different from `mpsc`, where there is one receiving endpoint and each queued value is consumed once.

Broadcast is also **bounded**. Slow receivers do not apply backpressure to senders. If a receiver falls farther behind than the retained history, old values are evicted and that receiver gets `RecvError::Lagged` telling it how many messages were skipped.

## Bad: Treating MPSC as Pub/Sub

<!-- rust-check: compile_fail; reason=tokio mpsc receivers are single-consumer and cannot be cloned -->
```rust
use tokio::sync::mpsc;

let (_tx, rx) = mpsc::channel::<i32>(16);
let _second_subscriber = rx.clone();
```

If several consumers must each receive the same event, one `mpsc::Receiver` is the wrong delivery primitive.

## Good: Independent Broadcast Subscribers

<!-- rust-check: compile -->
```rust
use tokio::sync::broadcast;

#[derive(Clone, Debug, PartialEq, Eq)]
enum Event {
    UserLogin(u64),
}

async fn fan_out_once() {
    let (tx, mut audit_rx) = broadcast::channel::<Event>(16);
    let mut metrics_rx = tx.subscribe();

    tx.send(Event::UserLogin(42))
        .expect("two receivers are active");

    assert_eq!(audit_rx.recv().await.unwrap(), Event::UserLogin(42));
    assert_eq!(metrics_rx.recv().await.unwrap(), Event::UserLogin(42));
}
```

New subscribers only receive values sent **after** they subscribe. Broadcast is an event stream, not durable history.

## Storage and Cloning Semantics

Tokio stores each sent value **once** in the channel. A receiver gets a clone on demand when it receives that value. After every relevant receiver has consumed the value—or the value has been evicted from the bounded history—the channel can release it.

That is why `broadcast::channel` requires `T: Clone`, but it is incorrect to describe `Sender::send` as eagerly cloning the message once per subscriber.

For expensive-to-clone payloads, broadcast an `Arc<T>` so each receiver clones the pointer rather than the full payload.

<!-- rust-check: compile -->
```rust
use std::sync::Arc;
use tokio::sync::broadcast;

#[derive(Debug)]
struct Snapshot {
    bytes: Vec<u8>,
}

fn snapshot_bus() -> broadcast::Sender<Arc<Snapshot>> {
    let (tx, _rx) = broadcast::channel(32);
    tx
}
```

## Handle Lag Explicitly

A slow receiver can miss events. Treat that as part of the protocol rather than assuming infinite buffering.

<!-- rust-check: compile -->
```rust
use tokio::sync::broadcast::{self, error::RecvError};

async fn consume(mut rx: broadcast::Receiver<u64>) {
    loop {
        match rx.recv().await {
            Ok(value) => {
                let _ = value;
            }
            Err(RecvError::Lagged(skipped)) => {
                // Decide whether to resync state, record loss, or continue.
                let _ = skipped;
            }
            Err(RecvError::Closed) => break,
        }
    }
}
```

After `Lagged(n)`, the receiver remains subscribed and its cursor advances to the oldest value still retained.

If event loss is unacceptable, `broadcast` may be the wrong primitive; use durable storage, per-subscriber queues, acknowledgements, or another protocol that matches the reliability requirement.

## Subscription Is Not Application Readiness

A receiver existing, a channel being open, or a lower-level transport connecting does not prove that the application-level protocol is ready. If the protocol defines an explicit `Ready`, `Connected`, `Hello`, snapshot, or acknowledgement event, gate dependent work on that semantic event.

<!-- rust-check: compile -->
```rust
use tokio::sync::broadcast::{self, error::RecvError};

#[derive(Clone, Debug)]
enum ServiceEvent {
    Connected,
    Data(u64),
}

async fn wait_until_connected(
    mut events: broadcast::Receiver<ServiceEvent>,
) -> Result<(), RecvError> {
    loop {
        match events.recv().await? {
            ServiceEvent::Connected => return Ok(()),
            ServiceEvent::Data(value) => {
                // Data policy is application-specific; it is not a substitute
                // for the explicit readiness contract.
                let _ = value;
            }
        }
    }
}
```

The same distinction applies when the broadcast channel is fed by an external protocol. A WebSocket or SSE connection reaching its transport-level open state only establishes that the transport exists. If the peer sends an application-level handshake, wait for that handshake before claiming the application is connected.

This matters especially in tests: asserting transport readiness can make a protocol test false-green while the application handshake is misspelled, never subscribed to, or never emitted.

## Sending and Closing

`Sender::send` succeeds when at least one receiver is active and returns the number of active receivers observed for that send. It fails only when there are no active receivers; the unsent value is returned in `SendError<T>`.

Dropping all senders eventually causes receivers to return `RecvError::Closed` after retained messages have been drained.

<!-- rust-check: compile -->
```rust
use tokio::sync::broadcast;

fn publish_if_anyone_is_listening(tx: &broadcast::Sender<String>, text: String) {
    match tx.send(text) {
        Ok(receiver_count) => {
            let _ = receiver_count;
        }
        Err(error) => {
            let unsent = error.0;
            drop(unsent);
        }
    }
}
```

## Broadcast vs Watch vs MPSC

| Primitive | Delivery semantics | Slow consumer behavior |
|---|---|---|
| `mpsc` | each queued value consumed once | bounded sender waits for capacity |
| `broadcast` | each active subscriber gets each retained event | old events are evicted; receiver reports lag |
| `watch` | receivers care about latest state | intermediate values may be skipped |

Use `broadcast` for events where fan-out is required and bounded history / lag is an acceptable part of the contract.

## Observing Channel State

`Sender::receiver_count()` reports active receiver handles. `Sender::len()` reports values still queued because at least one relevant receiver has not consumed them (unless they were already evicted).

<!-- rust-check: compile -->
```rust
use tokio::sync::broadcast;

fn inspect() {
    let (tx, _rx) = broadcast::channel::<u64>(16);
    let _active_receivers = tx.receiver_count();
    let _queued_values = tx.len();
}
```

These are observations, not a backpressure mechanism. Broadcast senders do not wait for slow receivers. If `len()` is persistently high, investigate lag and the subscriber workload rather than inventing a universal percentage threshold.

## Scaling

Subscriber count, wakeups, and per-receiver cloning all have costs, but there is no useful universal cutoff such as “100 receivers.” Measure the actual event rate, payload cost, and receiver behavior.

Partition by topic when that matches application semantics—not because of a magic subscriber count. If most subscribers only care about one class of event, separate channels can reduce irrelevant wakeups and clones.

## See Also

- [async-mpsc-queue](./async-mpsc-queue.md) - Single-consumer queued work
- [async-watch-latest](./async-watch-latest.md) - Latest-value state distribution
- [async-bounded-channel](./async-bounded-channel.md) - Backpressure and bounded MPSC queues
