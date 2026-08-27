# async-watch-latest

> Use `watch` when receivers need the latest state, not a lossless history of every update

## Why It Matters

`tokio::sync::watch` stores one value. Each receiver independently tracks whether it has seen the current value, and a slow receiver may skip intermediate updates. That makes `watch` a strong fit for configuration, status, desired state, and other “latest value wins” data.

Do **not** describe watch receivers as seeing every change. If every event matters, use a queue/broadcast design whose lag and backpressure semantics match that requirement.

## Good: Observe the Latest Value

```rust
use tokio::sync::watch;

#[tokio::main]
async fn main() {
    let (tx, mut rx) = watch::channel(0_u32);

    tx.send(1).unwrap();
    tx.send(2).unwrap();
    tx.send(3).unwrap();

    rx.changed().await.unwrap();
    assert_eq!(*rx.borrow_and_update(), 3);
}
```

The receiver is guaranteed access to the latest retained value, not a separate delivery of `1`, `2`, and `3`.

## Receivers Track Seen State Independently

```rust
use tokio::sync::watch;

#[tokio::main]
async fn main() {
    let (tx, rx) = watch::channel("initial");
    let mut a = rx.clone();
    let mut b = rx;

    tx.send("new").unwrap();

    a.changed().await.unwrap();
    assert_eq!(*a.borrow_and_update(), "new");

    // `b` has its own seen/unseen state.
    b.changed().await.unwrap();
    assert_eq!(*b.borrow_and_update(), "new");
}
```

One receiver marking a value seen does not mark it seen for other receivers.

## `borrow` Versus `borrow_and_update`

`borrow()` returns the current value without marking it seen. `borrow_and_update()` returns the current value and marks that value seen for the receiver.

In a loop that waits on `changed()`, prefer `borrow_and_update()` when consuming the change:

```rust
use tokio::sync::watch;

async fn observe(mut rx: watch::Receiver<u32>) -> Vec<u32> {
    let mut values = Vec::new();

    while rx.changed().await.is_ok() {
        let value = *rx.borrow_and_update();
        values.push(value);
    }

    values
}

#[tokio::main]
async fn main() {
    let (tx, rx) = watch::channel(0_u32);
    let task = tokio::spawn(observe(rx));

    tx.send(1).unwrap();
    drop(tx);

    assert_eq!(task.await.unwrap(), vec![1]);
}
```

Using `borrow()` after `changed()` can be surprising if another update arrives between the two calls: `borrow()` may read that newer value without marking it seen, causing the next `changed()` to return immediately for a value the application already processed.

## Do Not Hold a `Ref` Across `.await`

The guards returned by `borrow()` and `borrow_and_update()` hold a read lock on the watched value. Keep them short-lived. Holding one across `.await` can block senders and, in environments that permit the resulting `!Send` future, can deadlock.

```rust
use tokio::sync::watch;

async fn use_value(value: Vec<u32>) -> usize {
    tokio::task::yield_now().await;
    value.len()
}

#[tokio::main]
async fn main() {
    let (_tx, rx) = watch::channel(vec![1, 2, 3]);

    // Clone (or otherwise copy out) what is needed while the guard is short-lived.
    let value = rx.borrow().clone();
    assert_eq!(use_value(value).await, 3);
}
```

Do not keep the `watch::Ref` itself alive across the await point.

## Conditional Updates with `send_if_modified`

`send_if_modified` gives the sender mutable access to the current value and notifies receivers only when the closure returns `true`.

```rust
use std::sync::Arc;
use tokio::sync::watch;

#[derive(Debug, PartialEq, Eq)]
struct Config {
    generation: u64,
}

#[tokio::main]
async fn main() {
    let (tx, mut rx) = watch::channel(Arc::new(Config { generation: 1 }));
    let candidate = Config { generation: 2 };

    let modified = tx.send_if_modified(|current| {
        if current.as_ref() != &candidate {
            *current = Arc::new(candidate);
            true
        } else {
            false
        }
    });

    assert!(modified);
    rx.changed().await.unwrap();
    assert_eq!(rx.borrow_and_update().generation, 2);
}
```

The closure must return `true` whenever it actually modifies the value. Mutating and then returning `false` creates a silent update that receivers are not notified about.

## Channel Closure and the Final Value

A watch channel retains a current value. `changed().await` returns an error once the channel is closed **and** the receiver has no unseen value left. Code that loops on `changed()` can therefore still observe the last unseen value before termination.

Also note a sender-side distinction: `Sender::send(value)` returns an error if there are no receivers and does not retain that failed value for future subscribers. Methods such as `send_replace`, `send_modify`, and `send_if_modified` can update the stored value even when no receiver currently exists.

## Waiting for a State Predicate

```rust
use tokio::sync::watch;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State {
    Starting,
    Ready,
    Failed,
}

async fn wait_ready(mut rx: watch::Receiver<State>) -> Result<(), &'static str> {
    loop {
        match *rx.borrow_and_update() {
            State::Ready => return Ok(()),
            State::Failed => return Err("failed"),
            State::Starting => {}
        }

        rx.changed().await.map_err(|_| "sender closed")?;
    }
}

#[tokio::main]
async fn main() {
    let (tx, rx) = watch::channel(State::Starting);
    tx.send(State::Ready).unwrap();
    assert_eq!(wait_ready(rx).await, Ok(()));
}
```

Checking the current value before waiting is important because the desired state may already have been published.

## `watch` Versus `broadcast` Versus `mpsc`

| Requirement | Usually consider |
|---|---|
| Every observer needs current/latest state | `watch` |
| Multiple observers need an event stream | `broadcast` |
| One consumer owns queued work | `mpsc` |
| Slow observer may skip intermediate updates | `watch` |
| Producer should experience queue backpressure | bounded `mpsc` (or another bounded queue) |

`broadcast` also has explicit lag behavior: a slow receiver can lose older messages and receive a lag error once capacity is exceeded. If events must be lossless, design backpressure/storage accordingly rather than assuming broadcast guarantees infinite history.

## Practical Guidance

- Use `watch` only when intermediate updates may be coalesced.
- Do not claim each receiver sees every send.
- Use `borrow_and_update()` when consuming a `changed()` notification in a loop.
- Keep `watch::Ref` guards short and never carry them across `.await`.
- Make `send_if_modified` return value match whether mutation actually occurred.
- Check the current value before awaiting a future state transition.

## See Also

- [async-broadcast-pubsub](./async-broadcast-pubsub.md) — Multi-receiver event streams
- [async-mpsc-queue](./async-mpsc-queue.md) — Queued single-consumer work
- [async-cancellation-token](./async-cancellation-token.md) — Cancellation state
