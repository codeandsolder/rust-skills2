# own-arc-shared

> Use `Arc<T>` when multiple owners may cross thread boundaries; add synchronization only for mutation that actually requires it

## Why It Matters

`Arc<T>` provides atomic reference-counted shared ownership. Cloning an `Arc` clones the ownership handle, not the underlying `T`, and the allocation remains alive until the last strong owner is dropped.

`Arc` makes ownership thread-safe; it does **not** make arbitrary interior mutation safe. Whether `Arc<T>` is `Send`/`Sync` still depends on `T`, and shared mutation generally needs an appropriate synchronization primitive or an internally thread-safe type.

## Bad: `Rc` Across Threads

```rust compile_fail
use std::rc::Rc;
use std::thread;

fn main() {
    let data = Rc::new(vec![1, 2, 3]);
    let other = Rc::clone(&data);

    thread::spawn(move || println!("{other:?}"));
}
```

`Rc` deliberately has non-atomic reference counts and cannot be sent between threads.

## Good: Shared Immutable Data With `Arc`

```rust
use std::sync::Arc;
use std::thread;

fn main() {
    let data = Arc::new(vec![1, 2, 3]);
    let other = Arc::clone(&data);

    let worker = thread::spawn(move || other.iter().sum::<i32>());

    assert_eq!(worker.join().unwrap(), 6);
    assert_eq!(data.len(), 3);
}
```

For immutable data, `Arc<T>` is often sufficient by itself.

## Shared Mutation: Choose the Synchronization Semantics

```rust
use std::sync::{Arc, Mutex};
use std::thread;

fn main() {
    let counter = Arc::new(Mutex::new(0u32));
    let mut workers = Vec::new();

    for _ in 0..4 {
        let counter = Arc::clone(&counter);
        workers.push(thread::spawn(move || {
            *counter.lock().unwrap() += 1;
        }));
    }

    for worker in workers {
        worker.join().unwrap();
    }

    assert_eq!(*counter.lock().unwrap(), 4);
}
```

A `Mutex` is not the automatic companion to every `Arc`. Read-mostly data may need no lock; atomics, channels, `RwLock`, concurrent collections, or ownership transfer may better express other workloads.

## Mutate Before Sharing When You Still Have Unique Ownership

```rust
use std::sync::Arc;

fn main() {
    let mut values = Arc::new(vec![1, 2, 3]);

    Arc::get_mut(&mut values).unwrap().push(4);
    assert_eq!(&*values, &[1, 2, 3, 4]);

    let clone = Arc::clone(&values);
    assert!(Arc::get_mut(&mut values).is_none());
    drop(clone);
    assert!(Arc::get_mut(&mut values).is_some());
}
```

`Arc::get_mut` is useful when uniqueness is part of the control flow. `Arc::make_mut` implements copy-on-write for `T: Clone` when cloning the pointee on contention is the desired policy.

## Zeroed and Uninitialized Allocation APIs

Current stable Rust can allocate `Arc` storage as `MaybeUninit<T>`. Use these APIs for deliberate initialization strategies, not as generic “faster allocation” switches.

For a type where the all-zero bit pattern is a valid value:

```rust
use std::sync::Arc;

fn main() {
    let zero = Arc::<u32>::new_zeroed();

    // SAFETY: every byte is zero, which is a valid initialized u32 value.
    let zero = unsafe { zero.assume_init() };
    assert_eq!(*zero, 0);

    let zeros = Arc::<[u32]>::new_zeroed_slice(4);
    // SAFETY: an all-zero bit pattern is valid for every u32 element.
    let zeros = unsafe { zeros.assume_init() };
    assert_eq!(&*zeros, &[0, 0, 0, 0]);
}
```

The allocation functions themselves are safe because the result is `MaybeUninit`; the unsafe boundary is `assume_init`, where you assert the bytes represent valid initialized `T` values. Zero is **not** a valid bit pattern for every Rust type.

If the destination will be fully written, initialize uninitialized slots instead of zeroing and then overwriting them:

```rust
use std::sync::Arc;

fn main() {
    let mut values = Arc::<[u32]>::new_uninit_slice(3);
    let slots = Arc::get_mut(&mut values).unwrap();
    slots[0].write(10);
    slots[1].write(20);
    slots[2].write(30);

    // SAFETY: every element was initialized above.
    let values = unsafe { values.assume_init() };
    assert_eq!(&*values, &[10, 20, 30]);
}
```

Do not call `assume_init` after partial initialization. For ordinary values, `Arc::new(value)` is simpler and lets the compiler optimize construction normally.

## Do Not Build Ad-Hoc Atomic `Arc` Containers From Raw Pointers

`Arc::into_raw` / `Arc::from_raw` are ownership-transfer primitives with strict provenance and exactly-once reconstruction requirements. Putting those pointers in an `AtomicPtr` does not by itself solve reclamation, ABA, null handling, or concurrent ownership bookkeeping.

Use a proven abstraction for atomically replaceable shared pointers, or design a synchronization protocol whose safety argument includes reclamation. Raw `Arc` pointers are an unsafe boundary, not a normal extension of `Arc`.

## Performance

`Arc::clone` increments an atomic strong count and is usually much cheaper than cloning `T`, but “cheap” is workload-dependent. In a hot loop, avoid repeated ownership-count changes when a borrowed `&Arc<T>` or `&T` is sufficient.

Likewise, prefer `Rc<T>` in genuinely single-threaded ownership graphs because it avoids atomic reference-count operations—but choose from semantics first and benchmark if the difference matters.

## See Also

- [own-rc-single-thread](./own-rc-single-thread.md) — single-threaded shared ownership
- [own-mutex-interior](./own-mutex-interior.md) — mutex-based interior mutability
- [async-clone-before-await](./async-clone-before-await.md) — ownership around async tasks
- [unsafe-maybeuninit](./unsafe-maybeuninit.md) — initialization invariants
