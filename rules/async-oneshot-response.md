# async-oneshot-response

> Use `tokio::sync::oneshot` when exactly one value should travel from one sender to one receiver, especially for actor-style request-response.

## Why It Matters

A Tokio oneshot channel communicates at most one value. The `Sender` is consumed by `send`, and the `Receiver` is itself a `Future` that resolves to that value or to `RecvError` if the sender disappears without sending.

This matches request-response naturally: put a `oneshot::Sender<Response>` inside the queued request, send the request to the service, then await the paired receiver.

`Sender::send` is synchronous and never waits for receiver progress. If the receiver has already been dropped, `send` returns the unsent value to the caller.

## Bad: Polling Shared State for One Result

<!-- rust-check: compile -->
```rust
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::time::{sleep, Duration};

async fn polling_response() -> u64 {
    let result = Arc::new(Mutex::new(None));
    let producer_result = Arc::clone(&result);

    tokio::spawn(async move {
        *producer_result.lock().await = Some(42_u64);
    });

    loop {
        if let Some(value) = *result.lock().await {
            return value;
        }

        // Polling adds latency/work and requires shared mutable state even
        // though exactly one value will ever be produced.
        sleep(Duration::from_millis(1)).await;
    }
}
```

A capacity-one `mpsc` can also carry one response, but its API represents a reusable queue. Use it when queue semantics are actually useful; do not use it merely because every async handoff looks like a queue.

## Good: One Sender, One Receiver, One Value

<!-- rust-check: compile -->
```rust
use tokio::sync::oneshot;

async fn one_response() -> Result<u64, oneshot::error::RecvError> {
    let (tx, rx) = oneshot::channel::<u64>();

    tokio::spawn(async move {
        let _ = tx.send(42);
    });

    rx.await
}
```

There is no async `send().await`: `send` consumes the sender immediately. Awaiting happens on the receiver side.

## Actor-Style Request-Response

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;
use tokio::sync::{mpsc, oneshot};

#[derive(Clone, Debug, PartialEq, Eq)]
struct Value(String);

enum Request {
    Get {
        key: String,
        reply: oneshot::Sender<Option<Value>>,
    },
    Set {
        key: String,
        value: Value,
        reply: oneshot::Sender<()>,
    },
}

async fn service(mut rx: mpsc::Receiver<Request>) {
    let mut store = HashMap::<String, Value>::new();

    while let Some(request) = rx.recv().await {
        match request {
            Request::Get { key, reply } => {
                // If the caller cancelled, returning the value from `send`
                // is usually harmless here; the service can simply discard it.
                let _ = reply.send(store.get(&key).cloned());
            }
            Request::Set { key, value, reply } => {
                store.insert(key, value);
                let _ = reply.send(());
            }
        }
    }
}

async fn get_value(
    tx: &mpsc::Sender<Request>,
    key: impl Into<String>,
) -> Result<Option<Value>, &'static str> {
    let (reply, response) = oneshot::channel();

    tx.send(Request::Get {
        key: key.into(),
        reply,
    })
    .await
    .map_err(|_| "service stopped")?;

    response.await.map_err(|_| "service dropped the reply")
}
```

This keeps ownership simple: the service owns its state, each request owns its reply sender, and the caller owns the matching receiver.

## Distinguish Request Failure From Reply Failure

There are usually two independent failure points:

1. sending the request to the service can fail because the request queue is closed;
2. awaiting the oneshot can fail because the reply sender was dropped without sending.

Keep those cases distinct when callers can respond differently.

<!-- rust-check: compile -->
```rust
use tokio::sync::{mpsc, oneshot};

#[derive(Debug)]
enum CallError {
    ServiceStopped,
    ReplyDropped,
}

enum Request {
    Ping { reply: oneshot::Sender<u64> },
}

async fn call(tx: &mpsc::Sender<Request>) -> Result<u64, CallError> {
    let (reply, response) = oneshot::channel();

    tx.send(Request::Ping { reply })
        .await
        .map_err(|_| CallError::ServiceStopped)?;

    response.await.map_err(|_| CallError::ReplyDropped)
}
```

## Add a Deadline at the Caller Boundary

<!-- rust-check: compile -->
```rust
use tokio::sync::{mpsc, oneshot};
use tokio::time::{timeout, Duration};

#[derive(Debug)]
enum CallError {
    ServiceStopped,
    ReplyDropped,
    Timeout,
}

enum Request {
    Ping { reply: oneshot::Sender<u64> },
}

async fn call_with_timeout(
    tx: &mpsc::Sender<Request>,
) -> Result<u64, CallError> {
    let (reply, response) = oneshot::channel();

    tx.send(Request::Ping { reply })
        .await
        .map_err(|_| CallError::ServiceStopped)?;

    timeout(Duration::from_millis(100), response)
        .await
        .map_err(|_| CallError::Timeout)?
        .map_err(|_| CallError::ReplyDropped)
}
```

Dropping the receiver on timeout is cancellation information for the producer: a later `send` returns its value because nobody is waiting anymore.

## Sender and Receiver Drop Semantics

<!-- rust-check: compile -->
```rust
use tokio::sync::oneshot;

async fn drop_cases() {
    // Sender disappears without sending: receiver gets RecvError.
    let (tx, rx) = oneshot::channel::<String>();
    drop(tx);
    assert!(rx.await.is_err());

    // Receiver disappears first: send returns the unsent value.
    let (tx, rx) = oneshot::channel::<String>();
    drop(rx);
    let unsent = tx.send(String::from("hello")).unwrap_err();
    assert_eq!(unsent, "hello");
}
```

## Detect Caller Cancellation Before Expensive Work

`Sender::is_closed()` is a cheap snapshot. `Sender::closed().await` waits asynchronously until the receiver is dropped.

<!-- rust-check: compile -->
```rust
use tokio::sync::oneshot;

async fn producer(mut tx: oneshot::Sender<Vec<u8>>) {
    tokio::select! {
        _ = tx.closed() => {
            // Caller no longer needs the result.
        }
        value = async { vec![0_u8; 1024] } => {
            let _ = tx.send(value);
        }
    }
}
```

The `closed()` branch borrows the sender mutably; the send branch consumes it. `tokio::select!` supports this ownership pattern directly.

## Racing a Receiver Is Cancellation-Safe

A oneshot `Receiver` can be selected by mutable reference and awaited again if another branch wins.

<!-- rust-check: compile -->
```rust
use tokio::sync::oneshot;
use tokio::time::{sleep, Duration};

async fn wait_with_periodic_work(
    mut rx: oneshot::Receiver<u64>,
) -> Result<u64, oneshot::error::RecvError> {
    loop {
        tokio::select! {
            result = &mut rx => return result,
            _ = sleep(Duration::from_millis(10)) => {
                // Do unrelated periodic work, then continue waiting.
            }
        }
    }
}
```

Awaiting `&mut Receiver` is cancellation-safe: if the sleep branch wins, the response remains receivable on the next loop iteration.

## Small Wrapper Pattern

<!-- rust-check: compile -->
```rust
use tokio::sync::oneshot;

struct RpcRequest<Req, Res> {
    request: Req,
    reply: oneshot::Sender<Res>,
}

impl<Req, Res> RpcRequest<Req, Res> {
    fn new(request: Req) -> (Self, oneshot::Receiver<Res>) {
        let (reply, response) = oneshot::channel();
        (Self { request, reply }, response)
    }

    fn respond(self, response: Res) -> Result<(), Res> {
        self.reply.send(response)
    }
}
```

Return the `send` result when a caller may care that the response was cancelled; deliberately discard it when cancellation is expected and no recovery is useful.

## See Also

- [async-mpsc-queue](./async-mpsc-queue.md) - Queue requests to an owner task
- [async-bounded-channel](./async-bounded-channel.md) - Queue capacity and overload policy
- [async-select-racing](./async-select-racing.md) - Cancellation-safe selection
