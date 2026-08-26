# async-tokio-fs

> Use `tokio::fs` for ordinary filesystem operations from async code; use dedicated async types for pipes/devices and other special files

## Why It Matters

Most operating systems do not expose ordinary filesystem operations through the same readiness APIs used for async sockets. Tokio therefore implements `tokio::fs` with ordinary blocking filesystem calls executed on its blocking thread pool (currently via `spawn_blocking`). This keeps those calls off async runtime workers while preserving an async API.

Calling `std::fs` directly inside a future blocks the worker executing that future. On a current-thread runtime this is especially severe: there is no other async worker to make progress until the call returns.

## Bad

```rust
use std::path::PathBuf;

async fn read_files(paths: &[PathBuf]) -> std::io::Result<Vec<String>> {
    let mut out = Vec::with_capacity(paths.len());
    for path in paths {
        // Blocks the async worker running this future.
        out.push(std::fs::read_to_string(path)?);
    }
    Ok(out)
}
```

## Good

```rust
use std::path::PathBuf;

async fn read_files(paths: &[PathBuf]) -> std::io::Result<Vec<String>> {
    let mut out = Vec::with_capacity(paths.len());
    for path in paths {
        out.push(tokio::fs::read_to_string(path).await?);
    }
    Ok(out)
}
```

This example is intentionally sequential. Whether several filesystem operations should be issued concurrently depends on the storage device, cache state, filesystem, and workload; “more concurrent reads” is not automatically faster.

## Ordinary File APIs

```rust
use tokio::io::{AsyncReadExt, AsyncWriteExt};

async fn copy_prefix() -> std::io::Result<()> {
    let bytes = tokio::fs::read("input.bin").await?;
    tokio::fs::write("copy.bin", &bytes).await?;

    let mut input = tokio::fs::File::open("input.bin").await?;
    let mut prefix = [0u8; 64];
    let n = input.read(&mut prefix).await?;

    let mut output = tokio::fs::File::create("prefix.bin").await?;
    output.write_all(&prefix[..n]).await?;
    output.flush().await?;
    Ok(())
}
```

`tokio::fs` also provides directory, metadata, rename, remove, and canonicalization operations. The same principle applies: use its async wrapper when the operation occurs on an async execution path and may block.

## Special Files Are Different

Tokio explicitly recommends `tokio::fs` for **ordinary files**. A named pipe, device, or other special file can block in ways that interact badly with the blocking pool and runtime shutdown.

Use a dedicated async abstraction when one exists—for example `tokio::net::unix::pipe` for Unix named pipes or `tokio::io::unix::AsyncFd` for a nonblocking file descriptor whose readiness can be driven by the OS.

<!-- rust-check: fragment; reason=Unix-only AsyncFd example requires a nonblocking OS file descriptor and platform-specific setup -->
```rust
use tokio::io::unix::AsyncFd;

let async_fd = AsyncFd::new(nonblocking_fd)?;
let mut guard = async_fd.readable().await?;
// Perform the nonblocking syscall, then clear readiness when appropriate.
guard.clear_ready();
```

Do not blindly send a potentially indefinite special-file read to `spawn_blocking`: blocking-pool work cannot generally be aborted once it has started.

## When `std::fs` Is Fine

Synchronous filesystem APIs are fine on a genuinely synchronous path, such as configuration loading before a runtime is entered:

```rust
fn load_config_before_runtime() -> std::io::Result<String> {
    std::fs::read_to_string("config.toml")
}
```

The relevant boundary is not file size. A tiny operation can still block unpredictably on cold storage, network filesystems, antivirus hooks, or filesystem contention; a large cached read may finish quickly. Avoid universal thresholds such as “under 1 KB is safe.”

## Batching Can Reduce Offload Overhead

If profiling shows that thousands of tiny synchronous operations spend significant time crossing into the blocking pool, batching them into one `spawn_blocking` job can be reasonable:

```rust
use std::path::PathBuf;

async fn read_batch(paths: Vec<PathBuf>) -> std::io::Result<Vec<String>> {
    tokio::task::spawn_blocking(move || {
        paths
            .iter()
            .map(std::fs::read_to_string)
            .collect::<std::io::Result<Vec<_>>>()
    })
    .await
    .expect("blocking task panicked")
}
```

Do this because measurement shows batching helps, not because of a fixed file-size cutoff.

## Blocking-Pool Interaction

`tokio::fs`, explicit `spawn_blocking`, some DNS resolution, and standard-stream operations can share runtime blocking-pool capacity. Setting `max_blocking_threads` too low can therefore delay unrelated operations. Apply workload-level backpressure to large batches instead of treating the runtime's global thread cap as the primary concurrency control.

## See Also

- [async-spawn-blocking](./async-spawn-blocking.md) — blocking-pool semantics
- [async-blocking-detection](./async-blocking-detection.md) — finding worker stalls
- [async-tokio-runtime](./async-tokio-runtime.md) — runtime configuration

## References

- [Tokio filesystem module](https://docs.rs/tokio/latest/tokio/fs/)
- [Tokio `spawn_blocking`](https://docs.rs/tokio/latest/tokio/task/fn.spawn_blocking.html)
