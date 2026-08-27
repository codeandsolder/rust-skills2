# err-clippy-unwrap-types

> Use `allow-unwrap-types` only for types where the project deliberately chooses a panic-on-error policy

## Why It Matters

Clippy's `unwrap_used` and `expect_used` restriction lints are intentionally broad. Sometimes a project has a type-specific policy where panicking is the desired response to that error. Current Clippy supports an `allow-unwrap-types` configuration list so those types can be exempted without disabling the lint everywhere.

This is a **lint policy**, not a safety proof. In particular, `Mutex::lock().unwrap()` means "panic if this lock is poisoned." A poisoned lock indicates that a thread panicked while holding exclusive access and the protected data may no longer satisfy its invariants. Whether to propagate that panic, repair the state, or continue with the guard is an application decision.

## Bad

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;
use std::sync::{Mutex, RwLock};

struct User;

struct AppState {
    cache: Mutex<Vec<u8>>,
    config: RwLock<String>,
}

fn use_state(state: &AppState) {
    let cache = state.cache.lock().unwrap();
    let config = state.config.read().unwrap();
    let _ = (cache.len(), config.len());
}

fn unchecked_lookup(map: &HashMap<u64, User>, id: u64) -> &User {
    map.get(&id).unwrap()
}
```

If the project responds by disabling `clippy::unwrap_used` globally, both the deliberate lock policy and unrelated unchecked lookups become invisible to that lint.

## Good

Keep the lint enabled:

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "warn"
```

Then configure the narrow type exemption in `clippy.toml` or `.clippy.toml`:

```toml
# This says that unwrap/expect on LockResult is an accepted project policy.
allow-unwrap-types = ["std::sync::LockResult"]
```

Now the code itself can remain ordinary Rust:

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;
use std::sync::{Mutex, RwLock};

struct User;

struct AppState {
    cache: Mutex<Vec<u8>>,
    config: RwLock<String>,
}

fn use_state(state: &AppState) {
    // With the Clippy configuration above, these are exempt because their
    // receiver type is LockResult. Runtime semantics are unchanged: poison
    // still causes a panic here.
    let cache = state.cache.lock().unwrap();
    let config = state.config.read().unwrap();
    let _ = (cache.len(), config.len());
}

fn unchecked_lookup(map: &HashMap<u64, User>, id: u64) -> &User {
    // HashMap::get returns Option, so this remains an unwrap_used violation.
    map.get(&id).unwrap()
}
```

`allow-unwrap-types` applies to both `unwrap_used` and `expect_used`.

## Where the Configuration Lives

Clippy documents `clippy.toml` and `.clippy.toml` configuration files. It starts searching from the first available location in this order:

1. `CLIPPY_CONF_DIR`,
2. `CARGO_MANIFEST_DIR`,
3. the current directory,

then walks upward through parent directories. Clippy currently labels this configuration-file interface unstable.

Do not put `allow-unwrap-types` under `[workspace.metadata.clippy]`, `[lints.clippy]`, or a target table in `.cargo/config.toml`. `[lints.clippy]` controls lint **levels**; `allow-unwrap-types` is a separate Clippy configuration value.

## Poisoning Policy Is the Real Decision

### Panic on poison

If a panic while holding the lock means the process/thread should not continue with potentially inconsistent state, `unwrap()` or an explanatory `expect()` is a coherent policy:

```rust
use std::sync::Mutex;

fn next_id(ids: &Mutex<u64>) -> u64 {
    let mut id = ids.lock().expect("id allocator state poisoned");
    *id += 1;
    *id
}
```

### Continue despite poison

`PoisonError::into_inner()` gives access to the guard despite poisoning. That is not automatically "safer" than panicking; it explicitly accepts possibly tainted state and should be justified by the protected invariant:

```rust
use std::sync::Mutex;

fn read_best_effort(cache: &Mutex<Vec<u8>>) -> usize {
    let guard = cache.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.len()
}
```

### Repair and clear poison

If the program can restore a known-good invariant, repair the state and then clear the poison flag:

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

Choose among these policies based on what a panic can do to the protected state, not merely to silence a lint.

## When to Use `allow-unwrap-types`

Use it when all of these are true:

- the lint is valuable for the rest of the codebase,
- the exempted type has a deliberate, documented panic policy,
- applying that policy uniformly to the whole type is appropriate.

If only one call site is exceptional, a local `#[expect(clippy::unwrap_used, reason = "...")]` is usually more precise than a type-wide exemption.

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Expected failures versus panic-worthy invariants
- [err-expect-not-allow](./err-expect-not-allow.md) — Prefer `#[expect]` for local lint exceptions
- [err-expect-bugs-only](./err-expect-bugs-only.md) — Using `expect()` for invariants
