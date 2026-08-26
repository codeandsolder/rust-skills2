# anti-unsafe-send-sync

> Don't use `unsafe impl Send` / `Sync` as a thread-safety shortcut

## Why It Matters

`unsafe impl Send` and `unsafe impl Sync` bypass the compiler's thread-safety checks entirely. A mistaken `unsafe impl` introduces data races, torn reads/writes, and undefined behavior — without any compiler warnings. These impls are **safety assertions** that you, the programmer, have verified the type is actually thread-safe. Do not use them to silence the compiler without proof.

## Bad

```rust
struct FfiWrapper {
    ptr: *mut c_void,
}

// UNSOUND: raw pointers are neither Send nor Sync
unsafe impl Send for FfiWrapper {}
unsafe impl Sync for FfiWrapper {}

// Shared across threads — data race!
let wrapper = Arc::new(FfiWrapper { ptr });
thread::spawn(move || {
    unsafe { (*wrapper.ptr).mutate(); }
});
thread::spawn(move || {
    unsafe { (*wrapper.ptr).read(); }
});
```

```rust
// Another common pattern: mutex-less interior mutability
struct Cache {
    inner: *mut HashMap<String, Data>,
}

unsafe impl Send for Cache {}   // But inner is *mut — not thread-safe
unsafe impl Sync for Cache {}   // Allows &Cache across threads → data race
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// Use safe synchronization primitives instead
use std::sync::Mutex;

struct FfiWrapper {
    inner: Mutex<*mut c_void>,
}

impl FfiWrapper {
    fn mutate(&self) {
        let ptr = *self.inner.lock().unwrap();
        // SAFETY: Mutex ensures exclusive access
        unsafe { (*ptr).mutate(); }
    }
}

// Mutex<T>: Send + Sync when T: Send, so this compiles safely
```

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// For FFI types that are genuinely thread-safe:
use std::sync::atomic::AtomicBool;

/// Wrapper around an FFI type that is documented as thread-safe.
struct FfiSafeWrapper {
    handle: *mut ffi::Context,
    _pinned: PhantomPinned,  // Not Send/Sync unless we say so
}

// SAFETY: The FFI documentation states that Context handles
// are thread-safe and can be sent between threads.
// Verified by reading the C library source (commit abc123).
unsafe impl Send for FfiSafeWrapper {}
unsafe impl Sync for FfiSafeWrapper {}
```

## Pattern: Audit Trail for Safety

When `unsafe impl Send/Sync` is genuinely necessary, document the justification:

```rust
/// SAFETY:
/// - `ffi::Context` uses internal locking (confirmed in C source v2.3, line 456).
/// - All mutation goes through the safe API which holds the internal mutex.
/// - The pointer is only dereferenced behind `Mutex` or `&self` methods.
/// - Verified with ThreadSanitizer on a 24-hour stress test (no races).
unsafe impl Send for FfiContextWrapper {}
unsafe impl Sync for FfiContextWrapper {}
```

## Pattern: Use Existing Safe Types

Instead of raw pointers with unsafe impls, restructure to use safe wrapper types:

```rust
// BAD: raw pointer + unsafe impls
struct Database {
    conn: *mut sqlite3,
}
unsafe impl Send for Database {}

// GOOD: use safe wrapper (e.g., rusqlite::Connection is already Send)
use rusqlite::Connection;
struct Database {
    conn: Connection,  // Already Send + Sync
}
```

## Alternatives

| Problem | Solution |
|---------|----------|
| Raw pointer shared state | `Mutex<T>`, `RwLock<T>` |
| FFI handle that is thread-safe | `unsafe impl` with safety comment |
| FFI handle that is NOT thread-safe | Use `Mutex<*mut T>` |
| Unsafe cell | `UnsafeCell<T>` with explicit sync |
| Don't know if FFI is thread-safe | Assume it isn't — use Mutex |

## Verification

```rust
// Compile-time check that a type is Send/Sync
fn assert_send<T: Send>() {}
fn assert_sync<T: Sync>() {}

assert_send::<FfiWrapper>();
assert_sync::<FfiWrapper>();

// Also: run with ThreadSanitizer to detect data races
// RUSTFLAGS="-Z sanitizer=thread" cargo test
```

## Detection

```toml
[lints.clippy]
unsafe_derive_deserialize = "deny"  # Related: don't unsafely derive
# Review all `unsafe impl Send/Sync` manually — no lint catches misuse
```

## See Also

- [unsafe-send-sync-manual](./unsafe-send-sync-manual.md) — Safe manual Send/Sync implementation
- [conc-atomic-ordering](./conc-atomic-ordering.md) — Use atomics for correct thread-safe access
- [unsafe-safety-comment](./unsafe-safety-comment.md) — Document safety invariants

## References

- [Rustnomicon: Send and Sync](https://doc.rust-lang.org/nomicon/send-and-sync.html)
- [Rust RFC 255: Send/Sync traits](https://github.com/rust-lang/rfcs/blob/master/text/0255-object-safety.md)
