# anti-block-on-async

> Don't use `handle.block_on()` inside async code

## Why It Matters

Calling `Handle::current().block_on(future)` inside an async context blocks the current task *and* the worker thread. It defeats the purpose of async — cooperative scheduling, backpressure, and cancellation — and can panic with "Cannot start a runtime from within a runtime" if the runtime doesn't support nested entry points (e.g., `current_thread` runtime).

## Bad

```rust
use tokio::runtime::Handle;

async fn fetch_data(url: &str) -> Result<Data, Error> {
    // BAD: block_on inside async — blocks worker thread
    let handle = Handle::current();
    handle.block_on(async {
        client.get(url).await?.json().await
    })
}

async fn process_batch(items: &[Item]) {
    for item in items {
        // BAD: block_on in a loop — defeats async entirely
        let result = Handle::current().block_on(process_item(item));
    }
}
```

```rust
// BAD: Nested runtime panic
#[tokio::main]
async fn main() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    // Panics: "Cannot start a runtime from within a runtime"
    let result = rt.block_on(async { fetch_data().await });
}
```

## Good

```rust
// GOOD: just .await — let the caller's runtime handle scheduling
async fn fetch_data(url: &str) -> Result<Data, Error> {
    client.get(url).await?.json().await
}

// GOOD: async loop — proper cooperative multitasking
async fn process_batch(items: &[Item]) {
    for item in items {
        process_item(item).await?;  // Yields to runtime between iterations
    }
}
```

## When `block_on` Is Appropriate

```rust
// OK: At the TOP LEVEL, outside async context
// This is the single entry point into the async runtime.
fn main() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        // Your async main
    });
}

// OK: In tests where there is no enclosing runtime
#[test]
fn test_async_fn() {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let result = rt.block_on(async { fetch_data("url").await });
    assert!(result.is_ok());
}

// OK: In Drop (only option, but still problematic — see anti-blocking-async-drop)
impl Drop for MyType {
    fn drop(&mut self) {
        if let Ok(handle) = Handle::try_current() {
            let _ = handle.block_on(async { self.cleanup().await });
        }
    }
}
```

## When NOT to Use `block_on`

| Context | Result |
|---------|--------|
| Inside `async fn` | Blocks worker — defeats async |
| Inside `#[tokio::main]` | Panics on nested runtime |
| Inside another `block_on` | Panics on nested runtime |
| Inside a Tokio task | Blocks the worker — starves other tasks |
| Inside a `tokio::test` | Panics on nested runtime |

## Pattern: Provide Both Sync and Async

If a library needs both sync and async consumers, provide separate methods:

```rust
impl Client {
    /// Async API — for use inside async contexts.
    pub async fn fetch(&self, url: &str) -> Result<Data, Error> {
        self.client.get(url).await?.json().await
    }

    /// Sync wrapper — for use from sync contexts.
    /// Creates a one-shot runtime internally (no nesting risk).
    pub fn fetch_blocking(&self, url: &str) -> Result<Data, Error> {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(self.fetch(url))
    }
}
```

## Detection

```toml
[lints.clippy]
blocking_in_async = "warn"  # Catches spawn_blocking and block_on inside async
```

## See Also

- [async-tokio-runtime](./async-tokio-runtime.md) — Configure Tokio runtime appropriately
- [async-blocking-detection](./async-blocking-detection.md) — Detect and prevent blocking in async code

## References

- [Tokio: Runtime nesting](https://docs.rs/tokio/latest/tokio/runtime/struct.Runtime.html#method.block_on)
- [Tokio: Handle::block_on](https://docs.rs/tokio/latest/tokio/runtime/struct.Handle.html#method.block_on)
