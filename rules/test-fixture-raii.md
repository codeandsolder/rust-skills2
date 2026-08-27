# test-fixture-raii

> Use RAII for owned test resources; do not confuse cleanup with safe mutation of process-global state

## Why It Matters

Tests often acquire resources that should be released on every ordinary scope exit: temporary directories, files, sockets, transactions, or server handles. Putting cleanup in `Drop` (directly or through a library type that already implements it) couples the lifetime of the cleanup action to the resource and also runs during normal panic unwinding.

RAII is not a universal teardown mechanism. It does not run after process abort/kill, and restoring process-global state in `Drop` does not make concurrent mutation of that state safe.

## Bad

```rust
use std::{fs, path::PathBuf};

fn test_body() {
    let path = PathBuf::from("/tmp/example-test-file");
    fs::write(&path, b"data").unwrap();

    assert_eq!(fs::read(&path).unwrap(), b"data");

    // This line is skipped if an earlier assertion panics.
    fs::remove_file(path).unwrap();
}

fn main() {}
```

Manual teardown at the end of a test is easy to bypass with early returns or panic unwinding.

## Good

```rust
use std::fs;
use tempfile::TempDir;

fn main() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("payload.txt");

    fs::write(&path, b"data").unwrap();
    assert_eq!(fs::read(&path).unwrap(), b"data");

    // TempDir removes the directory tree when it drops.
}
```

Prefer a well-tested resource type such as `tempfile::TempDir` when it already models the lifecycle you need. A fixture framework can create and inject such a value, but the cleanup guarantee comes from the value's ownership/`Drop` semantics, not from the fixture syntax itself.

## Custom Guards

A custom guard is useful when the resource's lifecycle is application-specific. Cleanup code in `Drop` should usually avoid panicking, especially because a second panic during unwinding can abort the process.

```rust
use std::{fs, io, path::{Path, PathBuf}};

struct RemoveOnDrop(PathBuf);

impl RemoveOnDrop {
    fn create(path: impl Into<PathBuf>, contents: &[u8]) -> io::Result<Self> {
        let path = path.into();
        fs::write(&path, contents)?;
        Ok(Self(path))
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for RemoveOnDrop {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn main() -> io::Result<()> {
    let path = std::env::temp_dir().join(format!("raii-example-{}", std::process::id()));
    let file = RemoveOnDrop::create(path, b"hello")?;
    assert_eq!(fs::read(file.path())?, b"hello");
    Ok(())
}
```

For real parallel test suites, use a collision-resistant temporary-resource library rather than inventing a process-id filename scheme; the custom example is about the guard shape, not temporary-name generation.

## Process Environment Is Different

In Edition 2024, `std::env::set_var` and `remove_var` are unsafe because mutating the process environment can be unsound when other threads may access it on some platforms. An `EnvGuard` that restores the old value on drop solves only logical cleanup; it does **not** establish the safety precondition for the mutations.

When the environment is needed only by a child process, configure that child's environment instead:

```rust
use std::process::Command;

fn command_for_test() -> Command {
    let mut command = Command::new("my-test-helper");
    command.env("MY_VAR", "test-value");
    command
}

fn main() {
    let _command = command_for_test();
}
```

If a test truly must mutate the current process environment, it needs a design that satisfies the platform/API safety contract and prevents conflicting access; merely serializing one test helper or adding a drop guard should not be presented as a general proof of soundness.

## Long-Lived Background Resources

A server guard often needs an explicit shutdown signal plus ownership of the join handle. Store the handle in an `Option` so `Drop` can take and join it without moving a field directly out of a borrowed `self`:

```rust
use std::{sync::mpsc::Sender, thread::JoinHandle};

struct TestServer {
    shutdown: Sender<()>,
    handle: Option<JoinHandle<()>>,
}

impl Drop for TestServer {
    fn drop(&mut self) {
        let _ = self.shutdown.send(());
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn main() {}
```

Whether blocking in `Drop` is acceptable depends on the test architecture. For async resources, explicit async shutdown may be clearer because `Drop` itself cannot `await`.

## Fixture Frameworks Are Orthogonal

`rstest` and similar libraries can reduce repetitive setup and parameterization. Use them when that improves test structure, but keep resource cleanup encoded in the values being passed around whenever practical. That makes the lifetime rule work regardless of how the test was invoked.

## See Also

- [test-rstest-fixtures](./test-rstest-fixtures.md) - rstest fixture system
- [test-arrange-act-assert](./test-arrange-act-assert.md) - Test structure
- [test-tokio-async](./test-tokio-async.md) - Async tests
- [test-mock-traits](./test-mock-traits.md) - Dependency test doubles
