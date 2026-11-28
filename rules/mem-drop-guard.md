# mem-drop-guard

> Use Rust 1.100 `DropGuard` for local unconditional cleanup and dismissible rollback; keep longer-lived ownership in dedicated RAII types

**Rule**: `mem-drop-guard`

## Why It Matters

`core::mem::DropGuard::new(value, closure)` runs the `FnOnce(T)` closure when the guard is dropped on ordinary control-flow exits, `?`, returns, and unwinding panics. Its `Deref` and `DerefMut` implementations allow continued use of the wrapped value. `DropGuard::dismiss(guard)` extracts the value without running the cleanup closure, **and drops the closure's captures**. It does not leak them.

Use it when a rollback or cleanup action is local, simple, and tied to a single scope. Use a named `Drop` owner for long-lived protocols or invariants needing a maintained abstraction.

## Good: Atomic Parsing with Rollback

<!-- rust-check: run -->
```rust
use std::mem::DropGuard;
use std::num::ParseIntError;

fn parse_all(out: &mut Vec<u32>, input: &[&str]) -> Result<(), ParseIntError> {
    let original_length = out.len();
    let mut out = DropGuard::new(out, move |out| out.truncate(original_length));
    for text in input {
        out.push(text.parse()?);
    }
    DropGuard::dismiss(out);
    Ok(())
}

fn main() {
    let mut values = vec![2];
    assert!(parse_all(&mut values, &["3", "bad"]).is_err());
    assert_eq!(values, [2]);
    assert!(parse_all(&mut values, &["3", "5"]).is_ok());
    assert_eq!(values, [2, 3, 5]);
}
```

## Boundaries

- Drop closures are not guaranteed to run when the process aborts, exits abruptly, or memory is intentionally leaked. A caller-forgettable guard cannot be the sole reason memory safety holds.
- Cleanup must remain correct if unwinding occurs while the partially mutated value is live; avoid panic-prone cleanup where possible.
- For async code, dropping a future may run the guard synchronously; do not put blocking I/O inside its closure. Make cancellation and external side effects explicit.
- `dismiss` means **commit**; use it only after all fallible work has completed.

## See Also

- [unsafe-unwind-safety](./unsafe-unwind-safety.md)
- [unsafe-untrusted-safe-code](./unsafe-untrusted-safe-code.md)

- [mem-drop-order](./mem-drop-order.md) — deterministic destruction order
- [async-cancel-safety](./async-cancel-safety.md) — aborting async work safely
- [test-fixture-raii](./test-fixture-raii.md) — fixture cleanup
