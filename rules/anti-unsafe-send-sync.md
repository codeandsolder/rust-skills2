# anti-unsafe-send-sync

> Never use `unsafe impl Send` or `unsafe impl Sync` merely to silence auto-trait errors; each impl is a safety contract that other unsafe code may rely on

## Why It Matters

`Send` and `Sync` are unsafe auto traits:

- `T: Send` means it is sound to transfer ownership of `T` to another thread;
- `T: Sync` means it is sound to share `&T` between threads (`&T: Send`).

Most ordinary Rust types acquire these traits automatically from their fields. A manual `unsafe impl` is needed only when the compiler cannot infer thread-safety from the representation but the type's **actual ownership, aliasing, mutation, and external-library contracts** make the assertion sound.

An incorrect impl can enable data races or other undefined behavior in completely safe downstream code.

## Raw Pointers Block Automatic `Send` and `Sync` Deliberately

Raw pointers are neither `Send` nor `Sync`. Their presence tells the compiler that ownership/aliasing is not represented by ordinary Rust types and therefore cannot be checked automatically.

```rust
use std::marker::PhantomData;
use std::rc::Rc;

struct ThreadAffineHandle {
    raw: *mut core::ffi::c_void,
    _not_send_or_sync: PhantomData<Rc<()>>,
}

fn main() {
    let handle = ThreadAffineHandle {
        raw: std::ptr::null_mut(),
        _not_send_or_sync: PhantomData,
    };
    assert!(handle.raw.is_null());
}
```

Do not add `unsafe impl Send/Sync` until the external handle's documented semantics and your wrapper invariants actually justify those properties.

The `PhantomData<Rc<()>>` marker can make thread-affinity intent explicit because `Rc<()>` is neither `Send` nor `Sync`. `PhantomPinned` is about pinning/`Unpin`; it is **not** a substitute for a Send/Sync marker.

## A Mutex Does Not Make a Non-`Send` Inner Type `Send`

This is a common and dangerous misconception:

```text
Mutex<*mut T>  // still not Send/Sync merely because there is a mutex
```

`Mutex<T>` is `Send` and `Sync` only when `T: Send`. Since raw pointers are not `Send`, wrapping a raw pointer in `Mutex` does not cause the missing auto traits to appear.

A mutex solves synchronized **access** to an already transfer-safe owned value. It cannot establish that an opaque FFI handle may legally move between threads, nor can it repair external thread-affinity requirements.

## Prefer Representations That Derive the Correct Auto Traits

When possible, wrap resources in safe Rust ownership types whose `Send`/`Sync` behavior already matches the resource:

```rust
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct SharedCounter {
    value: Arc<Mutex<u64>>,
}

impl SharedCounter {
    fn increment(&self) {
        *self.value.lock().unwrap() += 1;
    }

    fn get(&self) -> u64 {
        *self.value.lock().unwrap()
    }
}

fn assert_send<T: Send>() {}
fn assert_sync<T: Sync>() {}

fn main() {
    assert_send::<SharedCounter>();
    assert_sync::<SharedCounter>();

    let counter = SharedCounter { value: Arc::new(Mutex::new(0)) };
    counter.increment();
    assert_eq!(counter.get(), 1);
}
```

No manual unsafe impl is needed because the compiler can derive the auto-trait properties from safe fields.

## Keep Thread-Affine FFI Handles on Their Owner Thread

If an external API says a handle must be used only on the creating thread, the solution is usually **not** `unsafe impl Send`. Keep the handle in one worker thread and send commands/data to that worker.

```rust
use std::sync::mpsc;
use std::thread;

#[derive(Debug)]
enum Command {
    Add(u32),
    Read(mpsc::Sender<u32>),
    Stop,
}

fn main() {
    let (tx, rx) = mpsc::channel::<Command>();

    let worker = thread::spawn(move || {
        // A real thread-affine FFI handle would be created here and never leave
        // this thread. `state` stands in for operations performed through it.
        let mut state = 0_u32;

        while let Ok(command) = rx.recv() {
            match command {
                Command::Add(value) => state += value,
                Command::Read(reply) => {
                    let _ = reply.send(state);
                }
                Command::Stop => break,
            }
        }
    });

    tx.send(Command::Add(7)).unwrap();
    let (reply_tx, reply_rx) = mpsc::channel();
    tx.send(Command::Read(reply_tx)).unwrap();
    assert_eq!(reply_rx.recv().unwrap(), 7);
    tx.send(Command::Stop).unwrap();
    worker.join().unwrap();
}
```

This models thread affinity structurally: messages cross threads, the handle does not.

## A Sound Manual Impl Mirrors a Proven Ownership Model

Sometimes a type internally uses a raw pointer even though its semantics are equivalent to a safe owning pointer. A manual impl can then be appropriate if every invariant is established.

The following educational wrapper owns exactly one heap allocation and exposes only ordinary shared/mutable references, making its Send/Sync bounds analogous to `Box<T>`:

```rust
use std::marker::PhantomData;
use std::ops::{Deref, DerefMut};
use std::ptr::NonNull;

struct OwnedPtr<T> {
    ptr: NonNull<T>,
    _owner: PhantomData<Box<T>>,
}

impl<T> OwnedPtr<T> {
    fn new(value: T) -> Self {
        let raw = Box::into_raw(Box::new(value));
        Self {
            ptr: NonNull::new(raw).unwrap(),
            _owner: PhantomData,
        }
    }
}

impl<T> Deref for OwnedPtr<T> {
    type Target = T;

    fn deref(&self) -> &T {
        // SAFETY: `ptr` came from a live Box allocation exclusively owned by self;
        // shared access cannot mutate T except through T's own legal interior mutability.
        unsafe { self.ptr.as_ref() }
    }
}

impl<T> DerefMut for OwnedPtr<T> {
    fn deref_mut(&mut self) -> &mut T {
        // SAFETY: &mut self guarantees exclusive access to this owner and allocation.
        unsafe { self.ptr.as_mut() }
    }
}

impl<T> Drop for OwnedPtr<T> {
    fn drop(&mut self) {
        // SAFETY: this is the unique pointer returned by Box::into_raw, reclaimed once.
        unsafe { drop(Box::from_raw(self.ptr.as_ptr())) };
    }
}

// SAFETY: transferring the unique allocation is sound exactly when transferring T is sound.
unsafe impl<T: Send> Send for OwnedPtr<T> {}

// SAFETY: shared access through &OwnedPtr<T> exposes only &T, so sharing is sound
// exactly when shared access to T is sound.
unsafe impl<T: Sync> Sync for OwnedPtr<T> {}

fn assert_send<T: Send>() {}
fn assert_sync<T: Sync>() {}

fn main() {
    assert_send::<OwnedPtr<String>>();
    assert_sync::<OwnedPtr<String>>();

    let mut value = OwnedPtr::new(String::from("hello"));
    value.push_str(" world");
    assert_eq!(value.as_str(), "hello world");
}
```

The safety comments justify **Send and Sync separately**. Real FFI wrappers must additionally reason about the foreign library's ownership, aliasing, callback, destruction, and thread rules.

## `Send` and `Sync` Are Independent Claims

A handle can be movable between threads but not safely shareable, or shareable only behind additional synchronization. Never write both impls by habit.

For example, many exclusive resources are naturally `Send` but need not be `Sync`. Conversely, a type's internal API may permit safe shared access but have special transfer constraints imposed by an external runtime. Review each trait against the actual contract.

## Dynamic Testing Does Not Prove an Unsafe Impl

ThreadSanitizer, Loom, stress tests, Miri where applicable, and integration tests can reveal bugs. They cannot prove that an unsafe Send/Sync contract is sound for all schedules, inputs, platforms, or future safe APIs.

A safety argument must stand on documented invariants. Testing supplements that argument; it does not replace it.

## Compile-Time Assertions Are Useful After the Design Is Sound

```rust
use std::sync::Arc;

fn assert_send<T: Send>() {}
fn assert_sync<T: Sync>() {}

fn main() {
    assert_send::<Arc<String>>();
    assert_sync::<Arc<String>>();
}
```

These assertions guard expected auto-trait properties from accidental representation changes. They do not validate a manually asserted unsafe invariant by themselves.

## Practical Guidance

- Treat every `unsafe impl Send` / `unsafe impl Sync` as a safety proof obligation.
- Prefer safe fields that let Rust derive the correct auto traits automatically.
- Remember raw pointers are neither `Send` nor `Sync`.
- Remember `Mutex<T>` requires `T: Send`; `Mutex<*mut T>` does not magically become thread-safe.
- Keep thread-affine foreign handles on one thread and communicate via messages when appropriate.
- Justify `Send` and `Sync` separately from ownership, aliasing, mutation, destruction, callbacks, and foreign-library guarantees.
- Use explicit negative-auto-trait marker fields such as `PhantomData<Rc<()>>` when stable structural non-Send/non-Sync behavior is desirable.
- Treat sanitizer/stress testing as supplemental evidence, never the proof itself.

## See Also

- [unsafe-send-sync-manual](./unsafe-send-sync-manual.md) - Manual auto-trait implementations
- [unsafe-safety-comment](./unsafe-safety-comment.md) - Documenting safety invariants
- [conc-atomic-ordering](./conc-atomic-ordering.md) - Atomic synchronization
- [async-mpsc-queue](./async-mpsc-queue.md) - Message-passing ownership
