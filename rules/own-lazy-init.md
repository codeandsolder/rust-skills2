# own-lazy-init

> Use `LazyLock` for thread-safe lazy statics and `LazyCell` for local or thread-local lazy values; use `OnceLock`/`OnceCell` when initialization is imperative rather than tied to one initializer

## Why It Matters

`LazyLock<T, F>` and `LazyCell<T, F>` pair storage with a single initialization function and run that function on first access. They are convenient when the same value is conceptually “defined here, computed later.”

`LazyLock` is the synchronized form and can be used for ordinary shared statics when its `T`/initializer satisfy the required thread-safety bounds. `LazyCell` is deliberately `!Sync`; it belongs in local or thread-local single-threaded contexts, not as a normal shared `static`.

## Good: Thread-Safe Lazy Static

```rust
use std::collections::HashMap;
use std::sync::LazyLock;

static MIME_TYPES: LazyLock<HashMap<&'static str, &'static str>> = LazyLock::new(|| {
    HashMap::from([
        ("html", "text/html"),
        ("json", "application/json"),
    ])
});

fn main() {
    assert_eq!(MIME_TYPES.get("json"), Some(&"application/json"));
}
```

`LazyLock::new` is designed for this pattern: the initializer can be stored in a static definition and the value is synchronized on first force/dereference.

## Good: Local `LazyCell`

```rust
use std::cell::LazyCell;

fn main() {
    let expensive = LazyCell::new(|| {
        (0..100).map(|x| x * x).sum::<u64>()
    });

    assert_eq!(*expensive, 328_350);
}
```

There is no synchronization overhead because `LazyCell` is single-threaded. That is also why it is `!Sync` and cannot simply replace `LazyLock` in a shared static.

## Thread-Local Lazy Values

`thread_local!` can hold a separate lazy cell per thread:

```rust
use std::cell::LazyCell;

thread_local! {
    static SCRATCH: LazyCell<Vec<u8>> = const { LazyCell::new(Vec::new) };
}

fn main() {
    SCRATCH.with(|scratch| assert!(scratch.is_empty()));
}
```

Each thread owns its own `LazyCell`; no cross-thread sharing is involved.

## Inspect Initialization Without Forcing It

Current `get` APIs are associated functions taking the lazy wrapper explicitly. They return `None` when it has not yet been initialized.

```rust
use std::sync::LazyLock;

fn main() {
    let lazy = LazyLock::new(|| String::from("ready"));

    assert_eq!(LazyLock::get(&lazy), None);
    assert_eq!(LazyLock::force(&lazy), "ready");
    assert_eq!(LazyLock::get(&lazy).map(String::as_str), Some("ready"));
}
```

Likewise, use `LazyCell::get(&cell)` for `LazyCell`. Writing `lazy.get()` can resolve to methods on `T` through deref and accidentally force initialization or mean something entirely different, so use the associated-function spelling when inspecting the wrapper itself.

## `From<T>` (Rust 1.96+) Creates an Already-Initialized Lazy Value

`LazyLock::from(value)` and `LazyCell::from(value)` do **not** defer construction of `value`; the value has already been evaluated before `from` is called. They are useful when an API wants a lazy-wrapper type but the value is already available.

```rust
use std::cell::LazyCell;
use std::sync::LazyLock;

fn main() {
    let lock: LazyLock<String> = LazyLock::from(String::from("already built"));
    let cell: LazyCell<u32> = LazyCell::from(42);

    assert_eq!(LazyLock::get(&lock).map(String::as_str), Some("already built"));
    assert_eq!(LazyCell::get(&cell), Some(&42));
}
```

This is a **runtime conversion**, not a replacement for a const static initializer. Code such as:

```text
static NAME: LazyLock<String> = LazyLock::from("hello".to_string());
```

is not a valid stable static initialization pattern: `String` construction and the `From` call are runtime operations. For a lazy static, keep using `LazyLock::new(|| ...)`.

## `LazyLock` With Shared Ownership

A lazy global can itself contain an `Arc` when callers need owned shared handles:

```rust
use std::sync::{Arc, LazyLock};

static DATA: LazyLock<Arc<[u8]>> = LazyLock::new(|| {
    Arc::from(vec![1u8, 2, 3, 4].into_boxed_slice())
});

fn get_data() -> Arc<[u8]> {
    Arc::clone(&DATA)
}

fn main() {
    assert_eq!(&*get_data(), &[1, 2, 3, 4]);
}
```

Do not add `Arc` solely because a value is in `LazyLock`; the `Arc` is for owned sharing after initialization, not for making lazy initialization thread-safe.

## When `OnceLock` / `OnceCell` Fits Better

Use a once cell when the initializer is not naturally fixed at the declaration site—for example, configuration supplied by application startup.

```rust
use std::sync::OnceLock;

static SERVICE_NAME: OnceLock<String> = OnceLock::new();

fn configure(name: String) -> Result<(), String> {
    SERVICE_NAME.set(name).map_err(|value| value)
}

fn main() {
    configure("api".to_owned()).unwrap();
    assert_eq!(SERVICE_NAME.get().map(String::as_str), Some("api"));
}
```

`LazyLock` is ideal for “the initializer is known here.” `OnceLock` is ideal for “some later code supplies the value once.”

## Poisoning

If a `LazyLock`/`LazyCell` initialization function panics, the lazy value becomes poisoned and future attempts to force it panic. Do not use a lazy initializer as a retry loop for fallible startup work.

If initialization can fail in an expected way, consider storing a `Result<T, E>` as the lazy value or using an initialization API whose error/retry semantics match the application.

## Decision Guide

| Requirement | Typical type |
|---|---|
| Shared thread-safe lazy static | `LazyLock<T>` |
| Local single-threaded lazy value | `LazyCell<T>` |
| Per-thread lazy value | `thread_local!` + `LazyCell<T>` |
| Value provided imperatively once | `OnceLock<T>` / `OnceCell<T>` |
| Value always needed and const-constructible | ordinary `const` / `static` |

## See Also

- [own-arc-shared](./own-arc-shared.md) — shared ownership after initialization
- [own-rc-single-thread](./own-rc-single-thread.md) — single-threaded shared ownership
- [own-refcell-interior](./own-refcell-interior.md) — single-threaded interior mutability

## References

- [`std::sync::LazyLock`](https://doc.rust-lang.org/std/sync/struct.LazyLock.html)
- [`std::cell::LazyCell`](https://doc.rust-lang.org/std/cell/struct.LazyCell.html)
- [`std::sync::OnceLock`](https://doc.rust-lang.org/std/sync/struct.OnceLock.html)
