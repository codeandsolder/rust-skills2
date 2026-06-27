# closure-async-closures

> Use `async || {}` closures for futures that need to borrow from their environment; prefer them over `|| async {}` when captures span `.await` points

## Why It Matters

Async closures (`async || { }`) were stabilized in Rust 1.85 (February 2025). They return a `Future` when called, just as an `async fn` does. The critical advantage over a regular closure returning an `async` block (`|| async { }`) is that the async closure's body *is* the future — borrowed captures can span `.await` points inside the closure safely. With `|| async { }`, the inner `async` block cannot borrow from the closure's captures because the closure returns the future immediately and the borrow would not live long enough.

Async closures also come with dedicated `AsyncFn` / `AsyncFnMut` / `AsyncFnOnce` traits that correctly handle higher-ranked lifetime signatures — something the old two-generic `F: Fn() -> Fut, Fut: Future` pattern cannot express.

## Bad

```rust
use std::future::Future;

// Returns a future, but borrows cannot span .await:
fn run_bad(f: impl Fn() -> Future<Output = ()>) {
    // This bound cannot accept async closures that borrow
    // from their environment across await points.
}

fn example_bad() {
    let mut out = Vec::new();

    // The closure returns an async block — borrows inside
    // the block cannot reference `out` across an await:
    // let f = || async {
    //     out.push(compute().await);  // ERROR: `out` borrowed...
    // };                              // ...but does not live long enough
}
```

## Good

```rust
use std::future::Future;

// Use an async closure when the future needs to borrow captures.
fn example_good() {
    let mut out = Vec::new();

    let f = async || {
        // Borrows `out` by mutable reference across the .await:
        out.push(compute().await);
    };
    f().await;  // fine
}

async fn compute() -> String {
    String::from("result")
}
```

## Basic Patterns

### Immutable borrow

```rust
let prefix = String::from("item-");
let fetch = async || {
    // Borrows `prefix` by shared reference — works across await.
    format!("{prefix}-{}", load_id().await)
};
let result = fetch().await;
```

### Mutable borrow (only `FnOnce`)

When the returned future holds a mutable borrow of a capture, the async closure is *lending* and only implements `FnOnce` — it can be called exactly once:

```rust
let mut counter = 0u32;
let tick = async || {
    // The returned future borrows `counter` mutably,
    // so `tick` only implements FnOnce:
    counter += 1;
};
tick().await;
// tick().await;  // ERROR: use of moved value
```

### `move` variant

Use `async move || { }` when the closure must outlive the current scope (e.g. spawned to another thread):

```rust
let data = vec![1, 2, 3];
let handle = std::thread::spawn(async move || {
    // `data` is moved into the closure, then into the future.
    process(&data).await
});
```

### Parameterized async closures

Async closures accept arguments just like regular closures:

```rust
let calculate = async |x: i32, y: i32| -> i32 {
    let delay = load_delay().await;
    x + y + delay
};
let result = calculate(3, 4).await;
```

## Lending Restriction

An async closure whose returned future holds a reference (mutable or shared) to a capture is a **lending** async closure. Such closures implement `FnOnce` but **not** `FnMut` or `Fn`. This is a fundamental constraint: the existing `Fn`/`FnMut`/`FnOnce` traits are *giving* (the returned value cannot borrow from the closure), whereas async closures are inherently *lending* when their future uses captures.

If you need to call an async closure multiple times and it does not borrow from captures (i.e. all captures are moved or `Copy`), `FnMut` and sometimes `Fn` are available:

```rust
fn call_twice<F: AsyncFnMut()>(mut f: F) {
    // Can only pass closures that are NOT lending.
}
```

## Comparison: `async ||` vs `|| async {}`

| Aspect | `async || {}` | `|| async {}` |
|--------|--------------|---------------|
| Borrows across `.await` | ✅ Yes | ❌ No |
| Minimal allocation | ✅ Single future | ❌ Nested future |
| `AsyncFn` trait impl | ✅ Yes | ❌ No (uses `Fn`) |
| Higher-order signatures | ✅ With `AsyncFn` bounds | ❌ Broken lifetimes |
| Multiple calls with mutable borrow | ❌ Lending → `FnOnce` only | ✅ `FnMut` with owned captures |

## Key Points

- **Stable in Rust 1.85** (February 2025). Requires at least Edition 2021; no `#![feature(...)]` needed.
- **Async closures implement `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce`** — use these bounds in function signatures instead of `F: Fn() -> Fut, Fut: Future`.
- **Lending async closures only implement `FnOnce`.** If the returned future borrows from a capture, the closure cannot be called a second time via `FnMut` or `Fn`.
- **`async move || {}` moves captures into the closure**, then the future borrows from the closure's owned captures. Use this for thread safety (`Send` + `'static`).
- **Disjoint capture still applies** — async closures capture only the fields they use, not entire structs (same as regular closures in Edition 2021+). However, async closures always capture all *input arguments* even if unused.
- **Use `AsyncFn` bounds** for higher-order async function signatures where the old two-generic pattern fails.

## See Also

- [async-async-fn-bounds](async-async-fn-bounds.md) - `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce` bounds for function signatures
- [async-clone-before-await](async-clone-before-await.md) - when to clone vs use async closures
- [closure-fn-trait-bounds](closure-fn-trait-bounds.md) - choosing the weakest `Fn`/`AsyncFn` trait bound
- [closure-move-capture](closure-move-capture.md) - when to use `move` with closures
- [closure-disjoint-capture](closure-disjoint-capture.md) - precise capture of individual fields
