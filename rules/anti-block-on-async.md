# anti-block-on-async

> Don't call `block_on` from code that is already running asynchronously

## Why It Matters

`Runtime::block_on` and `Handle::block_on` are bridges from synchronous code into async execution. Calling them from code that is already executing inside an async runtime does not make the nested work “more synchronous”; it can block an executor worker and Tokio runtime-entry combinations can panic when a runtime is started from a thread that is already driving one.

Inside async code, await the future. Keep `block_on` at a deliberately synchronous boundary such as a process entry point or a synchronous API adapter whose caller is not already inside that runtime.

## Bad

```rust
use tokio::runtime::Handle;

async fn nested_blocking() {
    let handle = Handle::current();
    // BAD: trying to synchronously drive async work from inside async work.
    handle.block_on(async {
        tokio::task::yield_now().await;
    });
}
```

## Good

```rust
async fn fetch_value(value: u32) -> u32 {
    tokio::task::yield_now().await;
    value
}

async fn process_batch(items: &[u32]) -> Vec<u32> {
    let mut out = Vec::with_capacity(items.len());
    for &item in items {
        out.push(fetch_value(item).await);
    }
    out
}
```

Awaiting keeps scheduling under the enclosing runtime and preserves normal cancellation/cooperative-scheduling behavior.

## `block_on` at a Synchronous Boundary

```rust
fn main() {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    runtime.block_on(async {
        tokio::task::yield_now().await;
    });
}
```

A library that offers both synchronous and asynchronous APIs should generally make the boundary explicit rather than secretly nesting runtimes inside async code. If a synchronous wrapper creates/drives a runtime, document that it must not be called from an incompatible async runtime context.

## Async Cleanup Is Not a `block_on` Exception

Do not solve the inability to `.await` in `Drop` by calling `Handle::block_on` there. `Drop` runs synchronously on whichever thread drops the value, which may itself be a runtime worker. Design explicit async cleanup such as `close().await`; use `Drop` only for synchronous cleanup that is safe to perform immediately.

## Detection

Search/review for `block_on` calls whose call graph can originate in `async fn`, Tokio tasks, `#[tokio::main]`, or `#[tokio::test]`. The important question is whether the call is a true sync→async boundary or a nested runtime entry.

## See Also

- [async-tokio-runtime](./async-tokio-runtime.md) — Configure Tokio runtime appropriately
- [async-blocking-detection](./async-blocking-detection.md) — Detect blocking work in async systems
- [anti-blocking-async-drop](./anti-blocking-async-drop.md) — Make async cleanup explicit

## References

- [Tokio Runtime::block_on](https://docs.rs/tokio/latest/tokio/runtime/struct.Runtime.html#method.block_on)
- [Tokio Handle::block_on](https://docs.rs/tokio/latest/tokio/runtime/struct.Handle.html#method.block_on)
