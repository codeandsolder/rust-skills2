# async-cancel-safety

> Ensure futures used in `tokio::select!` branches are cancellation-safe

## Why It Matters

`tokio::select!` polls branch futures on the current task and drops the losing futures when the expression finishes. Dropping a future does not undo bytes consumed or messages removed. Cancellation safety depends on whether dropping and recreating the operation preserves the progress its caller needs. Check the whole operation across every `.await`, not just its individual primitives.

## Bad

```rust
use tokio::io::{AsyncReadExt, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc;

// Non-cancel-safe: read_exact borrows buf but tracks progress in its future.
// Dropping it loses that progress; retrying from buf[0] is not a continuation.
async fn bad_example(stream: &mut BufReader<TcpStream>, rx: &mut mpsc::Receiver<u8>) {
    let mut buf = [0u8; 1024];
    tokio::select! {
        // BUG: if the `recv` branch fires first, the bytes already read
        // into buf remain consumed, and returning drops buf too
        result = stream.read_exact(&mut buf) => {
            println!("read {} bytes", result.unwrap());
        }
        msg = rx.recv() => {
            println!("got message: {:?}", msg);
        }
    }
}
```

## Good

```rust
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::sync::mpsc;

// Buffer AND filled offset survive each select iteration.
// This protects branch cancellation, not cancellation of good_example itself.
async fn good_example<R: AsyncRead + Unpin>(
    stream: &mut R,
    rx: &mut mpsc::Receiver<u8>,
    mut on_frame: impl FnMut(&[u8]),
) -> std::io::Result<()> {
    let mut buf = [0u8; 1024];
    let mut filled = 0;
    let mut messages_open = true;

    loop {
        tokio::select! {
            n = stream.read(&mut buf[filled..]) => {
                // A cancelled pending read consumes no bytes. Once selected,
                // commit its byte count before the next await.
                let n = n?;
                if n == 0 {
                    return if filled == 0 {
                        Ok(())
                    } else {
                        Err(std::io::Error::new(
                            std::io::ErrorKind::UnexpectedEof,
                            "EOF inside a fixed-size frame",
                        ))
                    };
                }
                filled += n;
                if filled == buf.len() {
                    on_frame(&buf);
                    filled = 0;
                }
            }
            msg = rx.recv(), if messages_open => {
                match msg {
                    Some(value) => println!("got message: {value}"),
                    None => messages_open = false,
                }
            }
        }
    }
}
```

This loop handles fixed-size frames and disables the closed channel branch to avoid a busy loop. If the caller may cancel this entire function and then reuse the stream, keep the buffer **and offset** in connection-owned state passed by mutable reference instead. A local buffer outside one `select!` still disappears when its enclosing future is dropped. Length-prefixed protocols must also retain partially consumed headers and enforce a size limit before allocation.

## What Is and Is Not Cancel-Safe

| Operation | Cancel-safe? | Notes |
|---|---|---|
| `mpsc::Receiver::recv()` | Yes | drops nothing on cancel |
| `broadcast::Receiver::recv()` | Yes | position tracked in receiver |
| `watch::Receiver::changed()` | Yes | no data consumed on cancel |
| `&mut oneshot::Receiver` | Yes | retain the receiver across iterations; dropping the owned receiver closes it |
| `tokio::time::sleep` | Deadline-dependent | recreating a relative sleep postpones the deadline; retain a pinned sleep or reuse an absolute deadline |
| `AsyncReadExt::read()` | Yes | a cancelled pending read consumes no bytes; a completed read may be short |
| `AsyncReadExt::read_exact()` | **No** | may consume a prefix; dropping the future loses its progress bookkeeping |
| `AsyncReadExt::read_to_end()` | **No** | do not assume the borrowed destination makes restarting lossless |
| `tokio::sync::Mutex::lock()` | **No** | cancellation loses the waiter's queue position; repeated cancellation can starve acquisition |
| collecting into a `Vec` inside a future | **No** | partial state is inside the future |

## Patterns for Non-Cancel-Safe Operations

1. **Keep state outside the cancellation boundary** — preserve buffers, offsets, parser phase, and partial results in an owner that survives every allowed cancellation. Handle EOF and closed channels explicitly.

2. **Use a pinned future held across iterations** — pin the future once and reuse it:

```rust
use std::pin::pin;
use tokio::io::AsyncReadExt;

async fn pinned_read_example<R: AsyncReadExt + Unpin>(mut reader: R) -> std::io::Result<()> {
    let mut buf = [0u8; 64];
    let mut read_fut = pin!(reader.read_exact(&mut buf));
    let mut heartbeat = tokio::time::interval(std::time::Duration::from_secs(1));
    loop {
        tokio::select! {
            result = &mut read_fut => return result.map(|_| ()),
            _ = heartbeat.tick() => println!("still waiting"),
        }
    }
}
```

Pinning alone does not keep a future alive: retain it outside the loop, borrow it in each branch, and stop polling after completion. Cancelling the enclosing function still drops it.

3. **Retain a spawned task's handle** — select on `&mut JoinHandle` if the task should outlive a losing branch, and later join it or abort and join it deliberately. Dropping an owned handle detaches the task and discards your way to observe its result; spawning is not a substitute for lifecycle management.

## Sources

- [Tokio select cancellation safety](https://docs.rs/tokio/latest/tokio/macro.select.html#cancellation-safety)
- [Tokio AsyncReadExt](https://docs.rs/tokio/latest/tokio/io/trait.AsyncReadExt.html)

## See Also

- [async-select-racing](async-select-racing.md) - use `tokio::select!` for racing/timeouts
- [async-bounded-channel](async-bounded-channel.md) - use bounded channels for backpressure
- [async-no-lock-await](async-no-lock-await.md) - never hold locks across `.await`
