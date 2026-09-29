# err-clippy-unwrap-types

> Do not use Clippy's `allow-unwrap-types` to punch type-wide holes in a strict no-unwrap/no-expect policy

## Why It Matters

Clippy supports an `allow-unwrap-types` configuration list that exempts selected receiver types from `unwrap_used` and `expect_used`.

That is useful in codebases whose policy intentionally permits panic-style extraction for whole classes of values. It is the wrong tradeoff for strict AI-maintained code: a type-wide exemption is easy to grow, hard to review at the call site, and silently preserves hidden panic paths.

Keep the lint universal and handle the type's error semantics explicitly.

## Bad: Type-Wide Escape Hatch

```toml
# clippy.toml
allow-unwrap-types = ["std::sync::LockResult"]
```

With that configuration, every lock unwrap/expect becomes invisible to the restriction lints.

## Good: Keep the Policy Uniform

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
```

The rust-skills2 strict CI gate keeps these rules at compiler-level `deny` for proc-macro compatibility, then rejects handwritten `#[allow]`, `#[warn]`, and expectations of these non-negotiable lints before Clippy runs.

## Mutex Poisoning: Choose the Semantics Explicitly

### Best-effort continuation

If the protected state remains usable after poisoning, handle that branch visibly:

```rust
use std::sync::{Mutex, PoisonError};

fn read_best_effort(cache: &Mutex<Vec<u8>>) -> usize {
    let guard = cache.lock().unwrap_or_else(PoisonError::into_inner);
    guard.len()
}
```

This is a real policy decision: the code accepts possibly tainted state. The `unwrap_or_else` combinator handles the error branch; it is not panic extraction.

### Repair and clear poison

If the program can restore a known-good invariant, repair before continuing:

```rust
use std::sync::Mutex;

fn reset_after_poison(state: &Mutex<Vec<u8>>) {
    let mut guard = state.lock().unwrap_or_else(|mut poisoned| {
        poisoned.get_mut().clear();
        state.clear_poison();
        poisoned.into_inner()
    });
    guard.clear();
}
```

### Propagate or translate

When continuing is not safe, return a domain error from the operation rather than panicking on the lock result. This is often cleaner if a lock guards state whose invariants may have been interrupted by the original panic.

## Where the Configuration Lives

If maintaining a legacy codebase that already uses `allow-unwrap-types`, remember that it is a Clippy configuration value in `clippy.toml`/`.clippy.toml`, not a lint level under `[lints.clippy]`.

For strict rust-skills2 CI, the central action supplies its own Clippy configuration via `CLIPPY_CONF_DIR`; downstream repositories therefore cannot use local `allow-unwrap-types` to weaken the gate.

## Migration Pattern

```text
1. Remove allow-unwrap-types from Clippy configuration.
2. Run unwrap_used + expect_used as hard errors.
3. For every lock/result extraction, decide whether to recover, repair, propagate, or terminate at the top-level boundary.
4. Keep the policy universal instead of replacing the type-wide exemption with local expectations.
```

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Preserve failure channels
- [err-expect-not-allow](./err-expect-not-allow.md) — Narrow expectations for suppressible lints only
- [err-expect-bugs-only](./err-expect-bugs-only.md) — Explicit alternatives to panic-producing `expect()`
