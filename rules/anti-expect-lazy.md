# anti-expect-lazy

> Do not use `expect()` as a shortcut for either error handling or invariant enforcement

## Why It Matters

`.expect(message)` is still an implicit panic. The message improves diagnostics, but the caller still cannot see or choose the failure policy.

For strict AI-maintained code, handle the `Result`/`Option` explicitly. Propagate ordinary failures, encode invariants in types, and keep deliberate process termination at the application's outer boundary.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;

fn load_port(input: &str) -> u16 {
    input.parse().expect("invalid port")
}

fn read_config() -> String {
    fs::read_to_string("config.toml").expect("config not found")
}

fn lookup_user(users: &[u64], id: u64) -> u64 {
    *users.iter().find(|&&user| user == id).expect("user not found")
}
```

These messages describe the failure better than `unwrap()`, but all three APIs still hide panic control flow.

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

The caller can retry, report, default, translate, or terminate.

## Encode Invariants Instead of Re-Extracting Them

Do not validate a map and later `expect()` that a key is still present. Convert validated input into a representation that stores the guarantee directly.

```rust
use std::num::NonZeroUsize;

struct ValidatedConfig {
    port: u16,
    buffer_size: NonZeroUsize,
}

impl ValidatedConfig {
    fn new(port: u16, buffer_size: usize) -> Option<Self> {
        Some(Self {
            port,
            buffer_size: NonZeroUsize::new(buffer_size)?,
        })
    }
}

fn main() {
    assert!(ValidatedConfig::new(8080, 4096).is_some());
}
```

## Thread Creation: Preserve the Error

The free `std::thread::spawn` function panics internally if OS thread creation fails. When creation failure needs an explicit policy, use `thread::Builder::spawn`, which returns `io::Result<JoinHandle<T>>`.

```rust
use std::io;
use std::thread;

fn start_worker() -> io::Result<thread::JoinHandle<u32>> {
    thread::Builder::new()
        .name("worker".into())
        .spawn(|| 42)
}
```

A binary that cannot continue can report that error from its top-level runner and return a failure `ExitCode`; it does not need `expect()` in the worker setup.

## Joining a Thread Is a Real Failure Channel

`JoinHandle::join()` reports worker panic as a `Result`. Keep that distinction visible:

```rust
use std::thread;

fn run_worker() -> thread::Result<u32> {
    let handle = thread::spawn(|| 42);
    handle.join()
}

fn main() {
    assert_eq!(run_worker(), Ok(42));
}
```

A supervisor can then log, restart, isolate, or terminate deliberately.

## Mutex Poisoning Needs an Explicit Policy

If the protected state can safely be used after poisoning, say so in the recovery branch rather than using `expect()`:

```rust
use std::sync::{Mutex, PoisonError};

fn read_best_effort(cache: &Mutex<Vec<u8>>) -> usize {
    let guard = cache.lock().unwrap_or_else(PoisonError::into_inner);
    guard.len()
}
```

If the state may be inconsistent, propagate an error or rebuild it. `unwrap_or_else` is not panic extraction: the error branch is explicitly handled.

## Decision Guide

| Situation | Typical choice |
|---|---|
| Invalid user/config input | return/propagate an error |
| File/network/database failure | return/propagate or recover |
| Optional lookup miss | `Option` or domain error |
| Internal invariant | encode it in types/state; otherwise return an invariant error |
| Fixed literal | use an infallible constant/constructor where available |
| OS thread creation | `Builder::spawn` and handle its `io::Result` |
| Worker panic at `join()` | supervision policy handles the `Result` |
| Fatal application prerequisite | report at top level and return failure `ExitCode` |

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) — Explicit alternatives to panic-producing `expect()`
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Preserve failure channels
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Panic-style extraction anti-patterns
