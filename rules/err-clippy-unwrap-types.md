# err-clippy-unwrap-types

> Configure `allow-unwrap-types` to whitelist safe `unwrap()` calls while keeping real `unwrap_used` violations

## Why It Matters

`Mutex::lock().unwrap()`, `RwLock::read().unwrap()`, and similar calls are extremely common and intentionally safe: the `LockResult` / `PoisonError` wrapping is a Rust standard-library convention that is almost never handled in practice. Denying `clippy::unwrap_used` for these drowns teams in false positives. The `allow-unwrap-types` config (clippy PR #16605, merged 2026) lets you whitelist specific types while keeping the lint active for real logic errors.

## Bad

<!-- rust-check: fragment; reason=anti-pattern fragment uses surrounding input data -->
```rust
// No config — every Mutex lock triggers unwrap_used
fn handle_request(state: &AppState) {
    let data = state.cache.lock().unwrap(); // clippy warns: unwrap_used
    let reader = state.config.read().unwrap(); // clippy warns: unwrap_used
    process(data, reader);
}
```

Teams often respond by disabling `unwrap_used` entirely, which defeats the purpose.

## Good

```toml
# clippy.toml (or .clippy.toml at workspace root)
allow-unwrap-types = [
    "core::result::Result::<std::sync::PoisonError<std::sync::MutexGuard<_>>>",
    "core::result::Result::<std::sync::PoisonError<std::sync::RwLockReadGuard<_>>>",
    "core::result::Result::<std::sync::PoisonError<std::sync::RwLockWriteGuard<_>>>",
]
```

```toml
# Alternately, use the short form (applies to all generic params of the type)
allow-unwrap-types = [
    "std::sync::LockResult<std::sync::MutexGuard<_>>",
    "std::sync::LockResult<std::sync::RwLockReadGuard<_>>",
    "std::sync::LockResult<std::sync::RwLockWriteGuard<_>>",
]
```

Now `Mutex::lock().unwrap()` no longer triggers:

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// No false positive — LockResult is whitelisted
fn handle_request(state: &AppState) {
    let data = state.cache.lock().unwrap();    // OK: whitelisted type
    let reader = state.config.read().unwrap(); // OK: whitelisted type
    process(data, reader);
}

// But real logic errors still fire:
fn unchecked_lookup(map: &HashMap<u64, User>, id: u64) -> &User {
    map.get(&id).unwrap() // clippy warns: unwrap_used — not whitelisted!
}
```

## Cargo.toml Integration

```toml
[workspace.metadata.clippy]
# workspace-root clippy.toml equivalent (Cargo workspace, Rust 1.85+)
allow-unwrap-types = [
    "std::sync::LockResult<std::sync::MutexGuard<_>>",
]
```

Or for a single crate:

```toml
# .cargo/config.toml
[target.'cfg(all())'.clippy]
allow-unwrap-types = [
    "std::sync::LockResult<std::sync::MutexGuard<_>>",
]
```

## Recommended Lint Configuration

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"       # Deny real unwrap violations
expect_used = "warn"       # Warn on expect (opt-in for stricter teams)
```

This works because `allow-unwrap-types` is a configuration, not a suppression — it tells clippy that certain types are known-safe, so `unwrap_used` = "deny" stays effective for everything else.

## What About PoisonError Handling?

The standard library's `PoisonError` exists to detect poisoned mutexes (when another thread panicked while holding the lock). For most applications, the correct behavior is:

```rust
// Accept the poison — acquire the lock anyway
let data = state.cache.lock().unwrap_or_else(|e| e.into_inner());

// Or simply:
let data = state.cache.lock().unwrap(); // safe — see above
```

Real poisoning recovery is exceptionally rare in practice; the `allow-unwrap-types` whitelist reflects this reality.

## When Not to Use

- In `no_std` crates without mutex types
- In libraries where you want to force explicit poison handling
- In codebases that prefer `?` with custom error types for all lock operations

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Avoiding unwrap in production
- [err-expect-not-allow](./err-expect-not-allow.md) — Prefer #[expect] over #[allow]
- [err-expect-bugs-only](./err-expect-bugs-only.md) — When expect() is appropriate
- [lint-clippy](./lint-deny-correctness.md) — Compiler lint configuration
