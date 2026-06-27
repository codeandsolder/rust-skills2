# anti-blocking-async-drop

> Don't block, spawn, or do I/O in `Drop` of async types

## Why It Matters

`Drop::drop()` runs synchronously on the current thread — including inside a Tokio worker. Blocking (`std::thread::sleep`, synchronous mutex, I/O) blocks the entire worker thread, preventing other tasks from making progress. `tokio::spawn` in `Drop` is even worse: the spawned future may never run if the runtime is shutting down. Async cleanup must be explicit.

## Bad

```rust
use std::thread;
use tokio::runtime::Handle;

struct AsyncClient { /* ... */ }

impl Drop for AsyncClient {
    fn drop(&mut self) {
        // BLOCKS TOKIO WORKER: never do this
        std::thread::sleep(std::time::Duration::from_secs(1));

        // Even worse: spawn in Drop — may never run
        let handle = Handle::current();
        handle.block_on(async {
            self.flush().await;
        });
    }
}
```

## Good

```rust
struct AsyncClient { /* ... */ }

impl AsyncClient {
    /// Explicit async cleanup — caller must call this.
    pub async fn close(&mut self) -> Result<()> {
        self.flush().await?;
        self.shutdown().await?;
        Ok(())
    }
}

// In usage:
async fn use_client() {
    let mut client = AsyncClient::new();
    // ... work ...
    client.close().await?;  // Explicit, deterministic cleanup
    drop(client);            // Drop is a no-op
}
```

## Pattern: Track Whether Cleanup Is Needed

If you must ensure cleanup runs unless explicitly closed, use a flag:

```rust
struct AsyncClient {
    needs_cleanup: bool,
    // ...
}

impl AsyncClient {
    pub async fn close(&mut self) -> Result<()> {
        if self.needs_cleanup {
            self.flush().await?;
            self.needs_cleanup = false;
        }
        Ok(())
    }
}

impl Drop for AsyncClient {
    fn drop(&mut self) {
        if self.needs_cleanup {
            // Can't do async — log a warning
            tracing::warn!("AsyncClient dropped without calling close()");
        }
    }
}
```

## Pattern: Tokio Console Cleanup

If you must run async cleanup on drop (last resort), spawn it as a background task. But this is **not recommended** — the task may be cancelled or never run:

```rust
impl Drop for AsyncClient {
    fn drop(&mut self) {
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async {
                // May never complete
            });
        }
    }
}
```

## Decision Guide

| Situation | Action |
|-----------|--------|
| Sync data flush | OK in Drop (fast, no blocking) |
| File close | Usually OK (kernel handles it) |
| Network flush | Move to `async fn close()` |
| Async shutdown protocol | Move to `async fn close()` |
| Any blocking I/O | Move to `async fn close()` |
| Known runtime being dropped | Can't safely spawn — log warning |

## Detection

```toml
[lints.clippy]
await_holding_lock = "deny"
# No built-in lint for this pattern — code review is essential.
```

## See Also

- [async-blocking-detection](./async-blocking-detection.md) — Discover blocking in async via metrics
- [anti-block-on-async](./anti-block-on-async.md) — Don't use block_on inside async code
- [async-runtime-metrics](./async-runtime-metrics.md) — Monitor runtime health metrics

## References

- [Tokio: Drop and async cleanup](https://docs.rs/tokio/latest/tokio/runtime/struct.Runtime.html#dropping)
- [Rust Users Forum: Block on drop in tokio](https://users.rust-lang.org/t/common-newbie-mistakes-and-bad-practices-in-rust-bad-habits/65243)
