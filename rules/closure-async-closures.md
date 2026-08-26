# closure-async-closures

> Use async closures when a callback future needs to borrow from closure captures; use `AsyncFn*` bounds for higher-order async callbacks

## Why It Matters

Async closures (`async || { ... }`) stabilized in Rust 1.85. Like an `async fn`, calling one produces a future. Their important advantage over the older `|| async { ... }` pattern is **lending**: the future returned by an async closure can borrow from the closure's captured state.

That matters for callbacks which must keep a borrow of a captured value across an `.await`. Rust also provides the `AsyncFn`, `AsyncFnMut`, and `AsyncFnOnce` traits for higher-order APIs that accept asynchronous callables.

## Bad: A Regular Closure Returning an Async Block

A regular `FnMut` closure cannot generally return a future that borrows a captured mutable variable from the closure itself:

```rust,compile_fail
fn main() {
    let mut output = Vec::<String>::new();

    let mut push_later = || async {
        tokio::task::yield_now().await;
        output.push("done".to_owned());
    };

    let _future = push_later();
}
```

The future would escape the `FnMut` call while borrowing captured state from that closure call. An async closure can express this lending relationship directly.

## Good: Borrow Captures Across `.await`

```rust
async fn compute() -> String {
    tokio::task::yield_now().await;
    "result".to_owned()
}

async fn example() {
    let mut output = Vec::new();

    let mut push_result = async || {
        output.push(compute().await);
    };

    push_result().await;
}
```

Here the future returned by `push_result()` borrows the async closure's captured `output` for the lifetime of that call.

## Higher-Order Async Callbacks

Use the async-aware callable traits when an API should accept callbacks whose returned futures may borrow from their arguments or captures:

```rust
async fn apply_twice<F>(mut f: F) -> u32
where
    F: AsyncFnMut(u32) -> u32,
{
    let first = f(10).await;
    f(first).await
}

async fn demo() {
    let increment = async |value: u32| {
        tokio::task::yield_now().await;
        value + 1
    };

    assert_eq!(apply_twice(increment).await, 12);
}
```

The older pattern `F: Fn(A) -> Fut, Fut: Future<Output = R>` remains useful when the returned future does not need to borrow from the callable invocation. `AsyncFn*` is the natural bound when lending is part of the contract.

## Which Call Traits Are Implemented?

Async closures implement async callable traits according to how their captures are used, analogously to ordinary closures. Separately, whether an async closure can also implement the ordinary `Fn`/`FnMut` traits is restricted when its returned future borrows from captured state.

For example, mutable lending prevents repeated calls while an earlier returned future still owns that mutable borrow:

```rust
async fn increment_once() {
    let mut counter = 0u32;

    let mut increment = async || {
        tokio::task::yield_now().await;
        counter += 1;
    };

    increment().await;
    assert_eq!(counter, 1);
}
```

Do not reduce this to a blanket rule that “async closures with mutable captures are always `FnOnce`.” The implemented async call traits depend on capture/move behavior, and the compiler should be allowed to infer the weakest callable trait that the closure supports.

## `async move ||` and Background Work

`async move || { ... }` moves captured values into the **closure**. Calling that closure still returns a future which must be driven by an async executor.

Do **not** write `std::thread::spawn(async move || { ... })` expecting the async body to run. `std::thread::spawn` calls the closure synchronously and would merely return its future without polling it.

When you want one background async operation, spawning an async block is usually simpler:

```rust
async fn background_example() -> Result<u32, tokio::task::JoinError> {
    let data = vec![1u32, 2, 3];

    let handle = tokio::spawn(async move {
        tokio::task::yield_now().await;
        data.into_iter().sum::<u32>()
    });

    handle.await
}
```

Use an async closure instead when the callable itself must be stored, passed around, parameterized, or invoked by another API.

## Parameterized Async Closures

```rust
async fn calculate() {
    let add_after_yield = async |x: i32, y: i32| -> i32 {
        tokio::task::yield_now().await;
        x + y
    };

    assert_eq!(add_after_yield(3, 4).await, 7);
}
```

## Do Not Claim an Allocation Difference Without Measuring

Both async closures and regular closures returning async blocks are represented by compiler-generated closure/future types in ordinary use; neither syntax inherently implies a heap allocation. Choose between them for borrowing and API semantics, not because one is supposedly a "single future" while the other necessarily allocates or creates costly nesting.

## Decision Guide

| Need | Prefer |
|------|--------|
| Async callback future borrows captured state | `async || { ... }` |
| Higher-order async callback with lending | `AsyncFn*` bound |
| Simple one-off spawned operation | `tokio::spawn(async move { ... })` |
| Regular closure returning an owned/non-lending future | `|| async move { ... }` can be fine |
| Synchronous OS thread closure | ordinary closure; explicitly run an executor if async work is truly required there |

## Key Points

- Async closures and the `AsyncFn*` traits are stable since Rust 1.85.
- Their key ergonomic capability is allowing returned futures to borrow from closure captures and callback arguments.
- Ordinary `Fn`/`FnMut` bounds cannot express all lending async-callback relationships; use `AsyncFn*` where that relationship matters.
- `async move ||` moves captures into the closure, but calling it still returns a future that needs an executor.
- Do not use `std::thread::spawn(async || { ... })` as an async task-spawning primitive.
- Choose call-trait bounds from what callers need; do not mechanically force `FnOnce` merely because a callback is async.

## See Also

- [async-async-fn-bounds](async-async-fn-bounds.md) - `AsyncFn`/`AsyncFnMut`/`AsyncFnOnce` bounds
- [closure-fn-trait-bounds](closure-fn-trait-bounds.md) - choosing callable trait bounds
- [closure-move-capture](closure-move-capture.md) - capture ownership
- [async-clone-before-await](async-clone-before-await.md) - borrowing vs cloning before await

## References

- [Rust 1.85 announcement: async closures](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/#async-closures)
- [Rust Reference: async closure semantics](https://doc.rust-lang.org/reference/expressions/closure-expr.html#async-closure-semantics)
