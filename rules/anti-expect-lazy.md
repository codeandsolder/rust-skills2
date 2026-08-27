# anti-expect-lazy

> Do not use `expect()` for ordinary runtime failures; use it to document deliberate panic invariants

## Why It Matters

`.expect(message)` is still a panic. The message improves diagnostics, but it does not make a file, network, parsing, lookup, or resource failure recoverable.

Use ordinary error handling for failures callers are expected to encounter. Use `expect()` when the failure would mean an internal invariant or deliberately fatal process policy has been violated, and make the message describe that invariant.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;

fn load_port(input: &str) -> u16 {
    // User/configuration input can be invalid.
    input.parse().expect("invalid port")
}

fn read_config() -> String {
    // Missing files and I/O errors are environmental failures.
    fs::read_to_string("config.toml").expect("config not found")
}

fn lookup_user(users: &[u64], id: u64) -> u64 {
    // A normal lookup miss becomes a panic for no semantic reason.
    *users.iter().find(|&&user| user == id).expect("user not found")
}
```

The messages are better than `unwrap()` diagnostics, but these functions still choose panic as their API response to expected runtime states.

## Good

<!-- rust-check: compile -->
```rust
use std::fs;
use std::io;
use std::num::ParseIntError;

fn load_port(input: &str) -> Result<u16, ParseIntError> {
    input.parse()
}

fn read_config() -> Result<String, io::Error> {
    fs::read_to_string("config.toml")
}

fn lookup_user(users: &[u64], id: u64) -> Option<u64> {
    users.iter().copied().find(|&user| user == id)
}
```

The caller now chooses whether to retry, display an error, use a default, translate the failure into another error type, or terminate the program.

## `expect()` Is Appropriate for Deliberate Invariants

```rust
use std::collections::HashMap;
use std::num::NonZeroUsize;

struct ValidatedConfig {
    values: HashMap<String, String>,
}

impl ValidatedConfig {
    fn port(&self) -> &str {
        self.values
            .get("port")
            .expect("validated configuration must contain a port")
    }
}

fn fixed_buffer_size() -> NonZeroUsize {
    NonZeroUsize::new(4096).expect("4096 is nonzero")
}
```

The useful message states what must be true and therefore what invariant failed, rather than merely restating the lower-level error.

## Thread Creation: `spawn` Versus `Builder::spawn`

The free `std::thread::spawn` function returns a `JoinHandle<T>` directly. It does **not** return a `Result`, so this is invalid Rust:

```text
thread::spawn(|| work()).expect("failed to spawn thread")
```

The free function internally uses a default `Builder` and panics if OS thread creation fails. If creation failure should be recoverable, use `thread::Builder::spawn`, which returns `io::Result<JoinHandle<T>>`:

```rust
use std::io;
use std::thread;

fn start_worker() -> io::Result<thread::JoinHandle<u32>> {
    thread::Builder::new()
        .name("worker".into())
        .spawn(|| 42)
}
```

If a particular binary deliberately treats thread-creation failure as fatal, `expect()` can document that policy:

```rust
use std::thread;

fn start_required_worker() -> thread::JoinHandle<()> {
    thread::Builder::new()
        .name("required-worker".into())
        .spawn(|| {})
        .expect("required worker thread must be creatable")
}
```

That is an application policy choice, not a universal statement that thread-spawn failures are unrecoverable.

## Joining a Thread Is a Different Failure

`JoinHandle::join()` returns a `Result` because the worker may have panicked. Calling `expect()` on `join()` means the caller deliberately propagates worker panic as a panic in the joining thread:

```rust
use std::thread;

fn run_worker() -> u32 {
    let handle = thread::spawn(|| 42);
    handle.join().expect("worker thread must not panic")
}
```

Sometimes that is exactly the desired invariant. In other systems, the join error should be logged, translated, or isolated instead.

## Mutex Poisoning Is Also a Policy Choice

```rust
use std::sync::Mutex;

fn increment(counter: &Mutex<u64>) {
    // Panic-on-poison is coherent when a panic while holding the lock may have
    // invalidated the protected invariant.
    let mut guard = counter.lock().expect("counter state poisoned");
    *guard += 1;
}
```

Do not generalize this into “mutex poisoning always means a bug” or “poison can always be ignored.” The correct response depends on what invariants the protected state has.

## Decision Guide

| Situation | Typical choice |
|-----------|----------------|
| Invalid user/config input | Return/propagate an error |
| File/network/database failure | Return/propagate or recover |
| Optional lookup miss | `Option` or domain error |
| Internal invariant after validation | `expect()` can be appropriate |
| Fixed literal known valid by construction | `expect()` can document the assumption |
| OS thread creation | `Builder::spawn` if recoverable; `expect()` only for deliberate fatal policy |
| Worker panic at `join()` | Handle or `expect()` according to supervision policy |

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) — Bug-class invariants
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Expected failure versus panic policy
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Panic-style extraction anti-patterns
