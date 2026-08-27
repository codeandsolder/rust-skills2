# anti-empty-catch

> Do not accidentally discard errors; make best-effort and discard semantics explicit

## Why It Matters

A `Result` carries information about whether an operation succeeded. Silently losing that information can hide a bug, but not every error must be propagated or logged. Cleanup, telemetry, cache warming, shutdown, and other best-effort operations may deliberately ignore failure.

The important distinction is **accidental loss** versus an **intentional API policy**. Code should make that policy legible at the point where the error stops mattering.

## Bad

<!-- rust-check: compile -->
```rust
use std::fs;
use std::io;
use std::path::Path;

fn write_cache(path: &Path, data: &[u8]) -> io::Result<()> {
    fs::write(path, data)
}

fn refresh_index() -> Result<usize, &'static str> {
    Err("index service unavailable")
}

fn do_work(cache: &Path) {
    // BAD: this looks like an ordinary operation, but all failures disappear
    // and there is no indication that best-effort behavior was intended.
    let _ = write_cache(cache, b"value");

    // BAD: converting to Option throws away the error merely to avoid dealing
    // with it. If the caller needs to distinguish failure, keep the Result.
    let value = refresh_index().ok();
    let _ = value;

    // BAD: an empty error branch gives reviewers no clue whether failure was
    // considered or simply forgotten.
    if let Err(_) = refresh_index() {
    }
}
```

These constructs are all valid Rust. The problem is that the surrounding code gives no evidence that losing the error is part of the intended contract.

## Good

<!-- rust-check: compile -->
```rust
use std::fs;
use std::io;
use std::path::Path;

fn write_cache(path: &Path, data: &[u8]) -> io::Result<()> {
    fs::write(path, data)
}

fn required_update() -> Result<(), io::Error> {
    fs::write("state.bin", b"updated")
}

fn save_required_state() -> Result<(), io::Error> {
    // Propagate when failure is part of this function's contract.
    required_update()?;
    Ok(())
}

fn remove_stale_cache(path: &Path) {
    // INTENTIONAL: stale cache cleanup is best-effort; a later cache miss will
    // rebuild it. `let _ =` explicitly acknowledges the must-use Result.
    let _ = fs::remove_file(path);
}

fn remove_stale_cache_explicit(path: &Path) {
    // If immediate disposal itself matters to readability, `drop` makes the
    // discard operation even more explicit.
    drop(fs::remove_file(path));
}
```

Do not add logging mechanically. Libraries may not own a logging policy, and high-volume best-effort paths can turn harmless failures into noisy telemetry. Log when the information is operationally useful; propagate, aggregate, count, retry, or deliberately discard when those semantics are more appropriate.

## Preserve Error Information Until You Intentionally Stop Needing It

Converting `Result<T, E>` to `Option<T>` with `.ok()` is appropriate when the caller genuinely only cares whether a value exists:

```rust
fn parse_optional_port(text: Option<&str>) -> Option<u16> {
    text.and_then(|text| text.parse::<u16>().ok())
}
```

Here the API deliberately collapses “missing” and “invalid” into `None`. If callers need to distinguish those states, returning a `Result` is the better contract.

## Batch Operations

When partial failure matters, collect or summarize it instead of stopping at the first error or silently discarding each one:

```rust
fn validate_batch(values: &[&str]) -> (Vec<u32>, Vec<&str>) {
    let mut successes = Vec::new();
    let mut failures = Vec::new();

    for &value in values {
        match value.parse::<u32>() {
            Ok(parsed) => successes.push(parsed),
            Err(_) => failures.push(value),
        }
    }

    (successes, failures)
}
```

Whether the final API returns the failures, logs a summary, exports a metric, or tolerates them is a product/domain decision.

## Rust Lints and `let _ =`

Rust 1.98's relevant lints have deliberately different policies:

- `unused_must_use` is **warn by default**. A bare discarded `Result` such as `operation();` warns, and rustc explicitly suggests `let _ = operation();` when the discard is intentional.
- `let_underscore_lock` is **deny by default**. `let _ = mutex.lock()` immediately drops the guard, which is commonly an accidental unlock.
- `let_underscore_drop` is **allow by default**. Projects can opt into it to flag `let _ = value_with_drop`; when immediate destruction is intentional, `drop(value)` is clearer.

Example project policy:

```toml
[workspace.lints.rust]
unused_must_use = "warn"
let_underscore_drop = "warn"
```

There is normally no reason to repeat `let_underscore_lock = "deny"` unless the workspace wants the choice documented explicitly, because that is already its default level.

## `let _ =` Is an Acknowledgment, Not an Error Handler

```rust
fn best_effort() -> Result<(), &'static str> {
    Err("optional operation failed")
}

fn caller() {
    // This intentionally suppresses the must-use warning. The comment supplies
    // the missing policy: failure does not affect the caller's contract.
    let _ = best_effort(); // best-effort prefetch; a miss falls back later
}
```

Use this when discard is genuinely the desired endpoint. Do not use it merely to make a compiler warning disappear.

## Decision Guide

| Situation | Typical action |
|-----------|----------------|
| Caller can/should react | Return or propagate the error |
| Local recovery exists | Handle/retry/fallback |
| Batch partial failure matters | Aggregate failures |
| Operational visibility matters | Log/metric/report |
| Failure is intentionally irrelevant | Explicitly discard, ideally with a short reason |
| You only need success/missing state | Converting to `Option` can be appropriate |

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — Error-returning APIs
- [err-context-chain](./err-context-chain.md) — Preserving context while propagating
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Panic-style extraction
