# unsafe-send-sync-manual

> Justify manual `Send`/`Sync` from invariants enforced by the type and its dependencies, not from hoped-for caller behavior

## Why It Matters

`Send` and `Sync` are unsafe auto traits. A manual implementation is a promise to every safe caller that moving or sharing the type across threads cannot violate Rust's aliasing and data-race rules.

That promise cannot depend on comments such as "callers put this in a `Mutex`" unless the API actually enforces that synchronization. Safe code is allowed to use a `Send`/`Sync` type in every way those traits permit.

## Bad

```rust
struct Buffer {
    ptr: *mut u8,
    len: usize,
}

// UNSOUND justification: nothing in Buffer requires callers to use a Mutex.
unsafe impl Send for Buffer {}
unsafe impl Sync for Buffer {}
```

External discipline that the type does not enforce is not a soundness invariant.

## Good: Invariant Comes From the Wrapped API

```rust
use std::ptr::NonNull;

mod ffi {
    pub enum Db {}
}

struct DatabaseHandle {
    raw: NonNull<ffi::Db>,
}

// SAFETY: the foreign database API's documented contract permits ownership of
// a handle to move between threads, and DatabaseHandle is the unique owner.
unsafe impl Send for DatabaseHandle {}

// SAFETY: the foreign database API documents concurrent operations on one
// handle as internally synchronized, and this Rust wrapper exposes no operation
// that violates that contract.
unsafe impl Sync for DatabaseHandle {}
```

The comments identify properties of the underlying resource and wrapper API that make the traits sound. If future methods break those properties, the unsafe impl must be reconsidered.

## Prefer Automatic Derivation

For ordinary Rust data, use fields whose own auto-trait implementations express the desired concurrency semantics:

```rust
use std::sync::{Arc, Mutex};

struct SharedState {
    value: Mutex<u64>,
}

fn share() -> Arc<SharedState> {
    Arc::new(SharedState { value: Mutex::new(0) })
}
```

No manual `unsafe impl` is needed.

## Key Points

- Prefer auto traits derived from fields.
- Manual `Send`/`Sync` must remain sound under all safe uses permitted by the public API.
- Do not rely on unenforced caller conventions for soundness.
- Document the invariant immediately above each unsafe impl and revisit it whenever fields or methods change.
- Raw pointers are a common reason to need manual reasoning, not a reason to blindly opt in.

## See Also

- [unsafe-safety-comment](unsafe-safety-comment.md) — document unsafe proofs
- [own-arc-shared](own-arc-shared.md) — thread-safe shared ownership
