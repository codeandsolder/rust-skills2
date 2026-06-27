# async-tokio-fs

> Use `tokio::fs` instead of `std::fs` in async code

## Why It Matters

`std::fs` operations are blocking—they stop the current thread until the syscall completes. In async code, this blocks the executor thread, preventing it from running other tasks. `tokio::fs` wraps filesystem operations in `spawn_blocking`, keeping the executor responsive.

## Bad

```rust
async fn process_files(paths: &[PathBuf]) -> Result<Vec<String>> {
    let mut contents = Vec::new();
    
    for path in paths {
        // BLOCKS the entire executor thread!
        let data = std::fs::read_to_string(path)?;
        contents.push(data);
    }
    
    Ok(contents)
}

// While reading a file, NO other tasks can run on this thread
```

## Good

```rust
use tokio::fs;

async fn process_files(paths: &[PathBuf]) -> Result<Vec<String>> {
    let mut contents = Vec::new();
    
    for path in paths {
        // Non-blocking: allows other tasks to run
        let data = fs::read_to_string(path).await?;
        contents.push(data);
    }
    
    Ok(contents)
}

// Even better: concurrent reads
async fn process_files_concurrent(paths: &[PathBuf]) -> Result<Vec<String>> {
    let futures: Vec<_> = paths.iter()
        .map(|path| fs::read_to_string(path))
        .collect();
    
    futures::future::try_join_all(futures).await
}
```

## tokio::fs API

```rust
use tokio::fs;

// Reading
let contents = fs::read_to_string("file.txt").await?;
let bytes = fs::read("file.bin").await?;

// Writing
fs::write("output.txt", "contents").await?;

// File operations
let file = fs::File::open("file.txt").await?;
let file = fs::File::create("new.txt").await?;

// Directory operations
fs::create_dir("new_dir").await?;
fs::create_dir_all("nested/dir/path").await?;
fs::remove_dir("empty_dir").await?;
fs::remove_dir_all("dir_with_contents").await?;

// Metadata
let metadata = fs::metadata("file.txt").await?;
let canonical = fs::canonicalize("./relative").await?;

// Rename/remove
fs::rename("old.txt", "new.txt").await?;
fs::remove_file("file.txt").await?;

// Read directory
let mut entries = fs::read_dir("some_dir").await?;
while let Some(entry) = entries.next_entry().await? {
    println!("{}", entry.path().display());
}
```

## Async File I/O

```rust
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt, AsyncBufReadExt, BufReader};

// Read with buffer
let mut file = File::open("large.bin").await?;
let mut buffer = vec![0u8; 4096];
let bytes_read = file.read(&mut buffer).await?;

// Read all
let mut contents = Vec::new();
file.read_to_end(&mut contents).await?;

// Write
let mut file = File::create("output.bin").await?;
file.write_all(b"data").await?;
file.flush().await?;

// Buffered line reading
let file = File::open("lines.txt").await?;
let reader = BufReader::new(file);
let mut lines = reader.lines();

while let Some(line) = lines.next_line().await? {
    println!("{}", line);
}
```

## When std::fs is Acceptable

```rust
// Startup/initialization (before async runtime)
fn main() {
    let config = std::fs::read_to_string("config.toml")
        .expect("config file required");
    
    tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(run_with_config(config));
}

// Single-threaded current_thread runtime (less impact)
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Still prefer tokio::fs, but impact is lower
}

// When file operations are rare and quick
// (e.g., reading small config once per hour)
```

## Performance Considerations

```rust
// tokio::fs uses spawn_blocking internally
// For many small files, the overhead adds up

// Batch operations when possible
let paths: Vec<_> = entries.iter()
    .map(|e| e.path())
    .collect();

let contents = futures::future::try_join_all(
    paths.iter().map(|p| fs::read_to_string(p))
).await?;

// For heavy I/O, consider memory-mapped files
// (requires unsafe or mmap crate)
```

## When std::fs Can Be Faster

For very small files (<1KB), `tokio::fs` adds `spawn_blocking` overhead that can exceed the actual I/O time. In these cases, `std::fs` wrapped in a single `spawn_blocking` call may be more efficient for batch reads:

```rust
// Tiny files: batch them into one spawn_blocking call
async fn read_tiny_files(paths: &[PathBuf]) -> io::Result<Vec<String>> {
    let paths = paths.to_vec();
    tokio::task::spawn_blocking(move || {
        paths.iter().map(|p| std::fs::read_to_string(p)).collect()
    })
    .await
    .unwrap()
}
```

## Do NOT Use tokio::fs for Special Files

`tokio::fs` wraps operations in `spawn_blocking`, which works for regular files but can hang indefinitely on **special files**:

```rust
// BAD: tokio::fs on special files can block forever
async fn bad_special() -> io::Result<()> {
    tokio::fs::read("/dev/tty").await?;  // May never return!
    Ok(())
}

// GOOD: Handle special files explicitly
async fn good_special() -> io::Result<Vec<u8>> {
    let data = tokio::task::spawn_blocking(|| {
        use std::os::unix::fs::FileTypeExt;
        let file = std::fs::File::open("/dev/something")?;
        let metadata = file.metadata()?;
        if metadata.file_type().is_char_device() || metadata.file_type().is_block_device() {
            // Use O_NONBLOCK or handle device-specific I/O
        }
        std::fs::read("/dev/something")
    }).await.unwrap()?;
    Ok(data)
}
```

Avoid `tokio::fs` for: named pipes (FIFOs), device files (`/dev/*`), `/proc` and `/sys` filesystems, and any file that may block on read/write indefinitely.

## See Also

- [async-spawn-blocking](./async-spawn-blocking.md) - How tokio::fs works internally
- [async-tokio-runtime](./async-tokio-runtime.md) - Runtime configuration
- [err-context-chain](./err-context-chain.md) - Adding path context to IO errors
