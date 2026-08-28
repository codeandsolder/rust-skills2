# async-tokio-fs

> Use `tokio::fs` for ordinary filesystem operations from async code; use dedicated async types for pipes/devices and other special files

## Why It Matters

Most operating systems do not expose ordinary filesystem operations through the same readiness APIs used for async sockets. Tokio therefore performs ordinary filesystem work through blocking operations offloaded from async workers. Calling `std::fs` directly inside a future can block the worker executing that future.

## Bad

```rust
use std::path::PathBuf;

async fn read_files(paths: &[PathBuf]) -> std::io::Result<Vec<String>> {
    let mut out = Vec::with_capacity(paths.len());
    for path in paths {
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

This is intentionally sequential. Whether several filesystem operations should be issued concurrently depends on the storage stack and workload; more concurrent reads are not automatically faster.

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

## Special Files Are Different

Named pipes, devices, and other special files can have blocking/readiness behavior that ordinary-file wrappers do not model well. Prefer a dedicated async abstraction when one exists—for example Tokio's Unix pipe support or `tokio::io::unix::AsyncFd` around a descriptor configured for nonblocking operation.

`AsyncFd` requires a Unix file descriptor that the OS readiness mechanism can poll, such as a socket or pipe, and the descriptor must already be nonblocking. Its readiness guards should be paired with an actual nonblocking I/O attempt; `try_io` clears stale readiness when that operation reports `WouldBlock`.

On this repository's pinned Linux verifier target, an anonymous Unix socket pair provides a self-contained real descriptor without external files or devices:

<!-- rust-check: compile -->
```rust
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use tokio::io::unix::AsyncFd;

async fn read_one_byte() -> io::Result<u8> {
    let (stream, mut peer) = UnixStream::pair()?;
    stream.set_nonblocking(true)?;

    // Make the wrapped descriptor readable before awaiting it.
    peer.write_all(&[42])?;
    let async_fd = AsyncFd::new(stream)?;

    loop {
        let mut guard = async_fd.readable().await?;
        let mut byte = [0u8; 1];

        match guard.try_io(|inner| inner.get_ref().read(&mut byte)) {
            Ok(result) => {
                result?;
                return Ok(byte[0]);
            }
            Err(_would_block) => continue,
        }
    }
}

fn main() {}
```

The socket is only a convenient verifier fixture; the same readiness discipline applies when wrapping a real nonblocking pipe/device descriptor that supports the platform's polling mechanism.

Do not blindly move a potentially indefinite special-file read into `spawn_blocking`: work that has begun in the blocking pool generally cannot be aborted by dropping its async handle.

## When `std::fs` Is Fine

Synchronous filesystem APIs are fine on a genuinely synchronous path, such as configuration loading before a runtime is entered:

```rust
fn load_config_before_runtime() -> std::io::Result<String> {
    std::fs::read_to_string("config.toml")
}
```

The relevant boundary is whether the operation may block an async worker, not a universal file-size threshold.

## Batching Can Reduce Offload Overhead

If profiling shows that many tiny synchronous operations spend significant time crossing into the blocking pool, batching them into one `spawn_blocking` job can be reasonable:

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

`tokio::fs`, explicit `spawn_blocking`, and some other runtime services may share blocking-pool capacity. Apply workload-level backpressure to large batches instead of treating the runtime's global thread cap as the primary concurrency control.

## See Also

- [async-spawn-blocking](./async-spawn-blocking.md) — blocking-pool semantics
- [async-blocking-detection](./async-blocking-detection.md) — finding worker stalls
- [async-tokio-runtime](./async-tokio-runtime.md) — runtime configuration
