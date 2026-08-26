# anti-blocking-async-drop

> Don't block or depend on asynchronous work completing from `Drop` of async types

## Why It Matters

`Drop::drop()` is synchronous and runs on the thread that drops the value. In an async program that may be an executor worker, so blocking I/O, sleeps, or nested runtime entry can stall unrelated tasks. Spawning async cleanup from `Drop` is also unreliable as a completion guarantee: the runtime may be shutting down, and `Drop` cannot await the spawned task.

Make required asynchronous cleanup an explicit operation. Keep `Drop` for fast synchronous resource release or best-effort diagnostics.

## Bad

```rust
use std::time::Duration;

struct AsyncClient;

impl Drop for AsyncClient {
    fn drop(&mut self) {
        // BAD: blocks whichever thread happened to drop the client.
        std::thread::sleep(Duration::from_secs(1));

        // Also bad as a correctness requirement: Drop cannot wait for this task.
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async {
                // Required cleanup cannot safely depend on this completing.
            });
        }
    }
}
```

## Good

```rust
use std::io;

struct AsyncClient {
    closed: bool,
}

impl AsyncClient {
    fn new() -> Self {
        Self { closed: false }
    }

    async fn flush(&mut self) -> io::Result<()> {
        tokio::task::yield_now().await;
        Ok(())
    }

    async fn shutdown(&mut self) -> io::Result<()> {
        tokio::task::yield_now().await;
        Ok(())
    }

    /// Required asynchronous cleanup is explicit and awaitable.
    pub async fn close(&mut self) -> io::Result<()> {
        self.flush().await?;
        self.shutdown().await?;
        self.closed = true;
        Ok(())
    }
}

async fn use_client() -> io::Result<()> {
    let mut client = AsyncClient::new();
    // ... use client ...
    client.close().await?;
    Ok(())
}
```

## Optional Diagnostic in `Drop`

If forgetting explicit cleanup is important, `Drop` can record a synchronous warning without pretending to finish async work:

```rust
struct Connection {
    closed: bool,
}

impl Drop for Connection {
    fn drop(&mut self) {
        if !self.closed {
            eprintln!("Connection dropped without explicit async close()");
        }
    }
}
```

Logging itself should remain appropriate for the environment; avoid a logger path that can block indefinitely during teardown.

## Decision Guide

| Situation | Preferred approach |
|-----------|--------------------|
| Memory/RAII handle release | ordinary `Drop` |
| OS handle whose close is synchronous | ordinary `Drop` |
| Protocol flush / graceful network shutdown | explicit `async fn close` |
| Required remote acknowledgement | explicit async operation |
| Blocking I/O or sleeps | never perform in async-type `Drop` |
| Best-effort background cleanup | only if loss is acceptable; do not treat spawn as a guarantee |

A useful API pattern is to make `close(self)` consume the object when possible, so successful explicit cleanup also prevents accidental reuse.

## See Also

- [async-blocking-detection](./async-blocking-detection.md) — Discover blocking in async code
- [anti-block-on-async](./anti-block-on-async.md) — Keep `block_on` at sync→async boundaries
- [async-runtime-metrics](./async-runtime-metrics.md) — Monitor runtime health
