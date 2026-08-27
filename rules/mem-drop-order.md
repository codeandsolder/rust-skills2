# mem-drop-order

> Know Rust's deterministic destruction order, and make resource dependencies explicit when one value must outlive another

## Why It Matters

Drop order is observable for RAII resources: lock guards unlock, transactions may roll back or commit, tracing guards close spans, and file/socket wrappers release operating-system resources.

The important design question is not merely “what drops first?” but **which resource must remain alive while another resource is being destroyed or finalized?** Encode that dependency clearly instead of relying on a comment that contradicts the code.

## Core Rules

For ordinary values:

- struct fields are dropped in **declaration order** after the struct's own `Drop::drop` method (if any) returns;
- tuple elements are dropped from first to last;
- local variables are normally dropped in reverse order of declaration when their scope ends;
- `drop(value)` can end a local value earlier by consuming it;
- temporary scopes have additional language rules and changed in some cases in Edition 2024, so do not summarize every temporary as “end of statement.”

These rules are deterministic, but pattern bindings, temporaries, partial moves, and control flow can make real code less obvious than a simple table suggests.

## Struct Fields: Dependency Goes First

If `child` must be dropped while `parent` is still alive, declare `child` before `parent`:

```rust
struct Child;
struct Parent;

impl Drop for Child {
    fn drop(&mut self) {
        println!("drop child");
    }
}

impl Drop for Parent {
    fn drop(&mut self) {
        println!("drop parent");
    }
}

struct Resources {
    // Fields drop in declaration order.
    child: Child,
    parent: Parent,
}

fn main() {
    let _resources = Resources {
        child: Child,
        parent: Parent,
    };
}
```

Here `child` is destroyed before `parent`.

Field order can also affect layout, especially with explicit representation attributes such as `#[repr(C)]`, so do not reorder fields casually in layout-sensitive types. A nested owner type can make lifetime/dependency structure clearer than relying on field order alone.

## Locals: Last Declared, First Dropped

For straightforward local bindings, declaration order gives stack-like destruction:

```rust
struct Resource(&'static str);

impl Drop for Resource {
    fn drop(&mut self) {
        println!("dropping {}", self.0);
    }
}

fn main() {
    let _connection = Resource("connection");
    let _transaction = Resource("transaction");
    let _statement = Resource("statement");

    // statement, then transaction, then connection
}
```

This is often useful when later resources depend on earlier ones.

## Explicit `drop` Must Match the Dependency

If a transaction needs a lock during commit, commit **before** releasing the lock:

```rust
use std::sync::Mutex;

fn update(shared: &Mutex<u32>) {
    let mut guard = shared.lock().unwrap();

    *guard += 1;
    // Finalize all work that requires protected state here.

    drop(guard); // unlock only after protected work is complete
}

fn main() {
    let value = Mutex::new(0);
    update(&value);
    assert_eq!(*value.lock().unwrap(), 1);
}
```

The previous version of this rule showed the opposite ordering—dropping a guard before a transaction it said depended on that guard. That defeats the purpose of controlling drop order.

Prefer an explicit smaller scope when it reads naturally:

```rust
use std::sync::Mutex;

fn read_then_continue(shared: &Mutex<Vec<u8>>) -> usize {
    let len = {
        let guard = shared.lock().unwrap();
        guard.len()
    }; // guard unlocks here

    len
}

fn main() {
    let values = Mutex::new(vec![1, 2, 3]);
    assert_eq!(read_then_continue(&values), 3);
}
```

Scopes make the lifetime visible without a standalone `drop(...)` call.

## `Drop::drop` Runs Before Fields Are Automatically Dropped

A custom destructor receives `&mut self` while all fields are still present. After it returns, fields are automatically destroyed in declaration order.

```rust
struct Inner;

impl Drop for Inner {
    fn drop(&mut self) {
        println!("inner field");
    }
}

struct Outer {
    inner: Inner,
}

impl Drop for Outer {
    fn drop(&mut self) {
        println!("outer Drop::drop");
    }
}

fn main() {
    let _outer = Outer { inner: Inner };
}
```

Do not attempt to move a normal field directly out of `self` inside `Drop::drop`; use an `Option<T>`, `mem::take`, `mem::replace`, or another ownership design when early extraction is required.

## `ManuallyDrop` Is an Unsafe Escape Hatch

`ManuallyDrop<T>` suppresses automatic destruction of `T`. Calling `ManuallyDrop::drop` is unsafe because you must ensure the value is not subsequently used or dropped again.

```rust
use std::mem::ManuallyDrop;

struct ResourcePair {
    child: ManuallyDrop<String>,
    parent: String,
}

impl Drop for ResourcePair {
    fn drop(&mut self) {
        // SAFETY: `child` is manually dropped exactly once and is never used again.
        unsafe { ManuallyDrop::drop(&mut self.child) };
        // `parent` is dropped automatically afterward.
    }
}

fn main() {
    let _pair = ResourcePair {
        child: ManuallyDrop::new("child".to_owned()),
        parent: "parent".to_owned(),
    };
}
```

Prefer ordinary ownership, field order, nested scopes, or `Option<T>` before reaching for `ManuallyDrop` just to control sequencing.

## `mem::forget` Is Not a Drop-Ordering Tool

`mem::forget(value)` intentionally prevents the value's destructor from running. It is safe to call because Rust never guarantees destructors will run, but it can leak memory or other resources. Use it only when intentionally transferring or abandoning ownership according to another API's contract—not as a convenient way to reorder cleanup.

## Edition 2024 Temporary Scope Changes

Edition 2024 changes the destruction point of some temporaries, including `if let` scrutinee temporaries and tail-expression temporaries. If correctness depends on a temporary guard's exact lifetime, bind it to a named local or introduce a block so the intended scope is explicit. See [lint-edition-2024](./lint-edition-2024.md) for migration guidance.

## Practical Guidance

- Model resource dependencies first: which value must outlive which?
- Use local scopes or explicit `drop` for important early release points.
- For structs, remember fields drop in declaration order; document non-obvious dependency ordering.
- Remember a custom `Drop::drop` runs before automatic field destruction.
- Avoid `ManuallyDrop` unless ordinary ownership cannot express the required behavior.
- Do not rely on oversimplified rules for temporary lifetimes; name important guards.

## See Also

- [mem-take-replace](./mem-take-replace.md) - Moving values out through replacement
- [own-mutex-interior](./own-mutex-interior.md) - Mutex ownership and guards
- [lint-edition-2024](./lint-edition-2024.md) - Edition 2024 temporary-scope changes
- [test-fixture-raii](./test-fixture-raii.md) - RAII cleanup in tests
