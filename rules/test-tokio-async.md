# test-tokio-async

> Use `#[tokio::test]` for ordinary Tokio-driven async tests, and configure the runtime flavor only when the test needs it

## Why It Matters

Calling an `async fn` produces a future; something still has to poll that future. Rust's built-in `#[test]` harness expects a synchronous test function, so Tokio tests commonly use `#[tokio::test]` to create a runtime and drive the async body.

A manually built runtime is valid when you need custom setup. `#[tokio::test]` is the concise default, not the only correct approach.

## Basic Async Test

```rust
async fn fetch_data() -> Result<&'static str, std::io::Error> {
    Ok("data")
}

#[tokio::test]
async fn fetches_data() {
    assert_eq!(fetch_data().await.unwrap(), "data");
}

fn main() {}
```

## Default Runtime Flavor

The default **test** runtime is `current_thread`: each `#[tokio::test]` gets a separate single-threaded runtime. This differs from `#[tokio::main]`, whose normal default is the multi-thread scheduler.

```rust
#[tokio::test]
async fn default_current_thread() {
    assert_eq!(2 + 2, 4);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn explicit_multi_thread() {
    let a = tokio::spawn(async { 20 });
    let b = tokio::spawn(async { 22 });
    assert_eq!(a.await.unwrap() + b.await.unwrap(), 42);
}

fn main() {}
```

Use the multi-thread flavor when the behavior under test actually depends on multiple worker threads, thread migration, or concurrent worker execution. Do not select it merely because the application uses a multi-thread runtime in production.

## Manual Runtime When You Need Builder Control

```rust
#[test]
fn manually_configured_runtime() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    runtime.block_on(async {
        tokio::task::yield_now().await;
        assert!(true);
    });
}

fn main() {}
```

The builder is useful for settings that the test attribute does not expose or when runtime ownership/lifetime is itself part of the test.

## Paused Time

Tokio's paused-time testing APIs require the `test-util` feature. `start_paused = true` starts the test runtime with time frozen, and `time::advance` moves Tokio's clock without sleeping in wall-clock time.

```rust
use tokio::time::{self, Duration};

#[tokio::test(start_paused = true)]
async fn advances_virtual_time() {
    let task = tokio::spawn(async {
        time::sleep(Duration::from_secs(60)).await;
        42
    });

    time::advance(Duration::from_secs(60)).await;
    assert_eq!(task.await.unwrap(), 42);
}

fn main() {}
```

A typical test dependency configuration is therefore:

```toml
[dev-dependencies]
tokio = { version = "1", features = ["macros", "rt", "time", "test-util"] }
```

Add `rt-multi-thread` only when tests request the multi-thread flavor.

## Testing Timeouts

```rust
use std::future::pending;
use tokio::time::{timeout, Duration};

#[tokio::test]
async fn timeout_triggers() {
    let result = timeout(Duration::from_millis(1), pending::<()>()).await;
    assert!(result.is_err());
}

#[tokio::test]
async fn operation_finishes_before_timeout() {
    let result = timeout(Duration::from_secs(1), async { 42 }).await;
    assert_eq!(result.unwrap(), 42);
}

fn main() {}
```

For timeout-heavy suites, paused time is often faster and less flaky than relying on tiny real-time durations.

## Testing Concurrent Work

`tokio::join!` polls several futures concurrently on the current task; it does not by itself move them onto worker threads.

```rust
async fn fetch_user(id: u64) -> Result<u64, std::io::Error> {
    tokio::task::yield_now().await;
    Ok(id)
}

#[tokio::test]
async fn joins_operations() {
    let (a, b) = tokio::join!(fetch_user(1), fetch_user(2));
    assert_eq!(a.unwrap(), 1);
    assert_eq!(b.unwrap(), 2);
}

fn main() {}
```

Use `tokio::spawn` when independent Tokio tasks are part of the behavior you need to test.

## Capturing Tracing Output

The `tracing-test` crate provides a purpose-built `#[traced_test]` attribute and injects helpers such as `logs_contain` for assertions. It works with async Tokio tests:

<!-- rust-check: compile -->
```rust
use tracing::info;
use tracing_test::traced_test;

async fn emit_completion_log() {
    info!(operation = "demo", "processing completed");
}

#[traced_test]
#[tokio::test]
async fn captures_logs() {
    emit_completion_log().await;
    assert!(logs_contain("processing completed"));
    assert!(!logs_contain("ERROR"));
}

fn main() {}
```

`tracing-test` installs filtering/capture behavior of its own. In integration tests, which compile as a separate crate from the library under test, consult its current `no-env-filter` guidance if you need to capture events emitted by the library crate rather than only the test crate.

For custom subscribers, be careful with scoped defaults and async work. A synchronous `with_default(|| async { ... })` call returns a future **after** the scoped default has been restored, so merely awaiting that returned future does not keep the subscriber installed. Use a guard whose lifetime actually covers polling, an instrumented future/dispatch, or a testing helper designed for async capture.

## Testing Channels

```rust
use tokio::sync::mpsc;

#[tokio::test]
async fn channel_communication() {
    let (tx, mut rx) = mpsc::channel(4);

    tokio::spawn(async move {
        tx.send("hello").await.unwrap();
        tx.send("world").await.unwrap();
    });

    assert_eq!(rx.recv().await, Some("hello"));
    assert_eq!(rx.recv().await, Some("world"));
    assert_eq!(rx.recv().await, None);
}

fn main() {}
```

## See Also

- [test-rstest-fixtures](./test-rstest-fixtures.md) - Parameterized tests and fixtures
- [async-tokio-runtime](./async-tokio-runtime.md) - Runtime configuration
- [test-mock-traits](./test-mock-traits.md) - Mocking async-facing abstractions
- [test-fixture-raii](./test-fixture-raii.md) - Test cleanup

## References

- [Tokio `#[test]` macro](https://docs.rs/tokio/latest/tokio/attr.test.html)
- [Tokio feature flags](https://docs.rs/tokio/latest/tokio/#feature-flags)
- [`tracing-test`](https://docs.rs/tracing-test/latest/tracing_test/)
