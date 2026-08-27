# async-fn-in-trait

> Use native `async fn` in traits for static dispatch when its return-future bounds fit the API

## Why It Matters

Rust has supported `async fn` and return-position `impl Trait` in traits since Rust 1.75. Native async trait methods avoid forcing one erased boxed-future representation on every statically dispatched call.

That does **not** make native async trait methods a universal replacement for `async-trait`. On Rust 1.98, a dispatchable trait method with an opaque return type—including an `async fn`—is still not dyn-compatible. Public APIs also need to decide which auto-trait bounds, especially `Send`, callers are allowed to rely on for the returned future.

Choose the representation from the API requirements rather than from a blanket “macro bad / native good” rule.

## Good: Native Async Trait for Static Dispatch

```rust
trait Repository {
    async fn get(&self, id: u64) -> String;
}

struct MemoryRepository;

impl Repository for MemoryRepository {
    async fn get(&self, id: u64) -> String {
        format!("row-{id}")
    }
}

async fn load(repo: &impl Repository) -> String {
    repo.get(7).await
}

#[tokio::main]
async fn main() {
    assert_eq!(load(&MemoryRepository).await, "row-7");
}
```

This path uses static dispatch. There is no trait-object vtable or mandatory heap allocation merely because the method is async.

## Native Async Methods Are Not Dyn-Compatible

The Rust Reference requires dispatchable trait-object methods not to have opaque return types. `async fn` has a hidden future type, so this remains invalid on Rust 1.98:

```rust,compile_fail
trait Repository {
    async fn get(&self, id: u64) -> String;
}

fn store(_: Box<dyn Repository>) {}

fn main() {}
```

If callers need `dyn Repository`, use an erased dyn-compatible representation or a crate such as `async-trait` that performs that erasure for you.

## Good: Manual Dyn-Compatible Boxed Future

```rust
use std::future::Future;
use std::pin::Pin;

type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

trait Repository {
    fn get(&self, id: u64) -> BoxFuture<'_, String>;
}

struct MemoryRepository;

impl Repository for MemoryRepository {
    fn get(&self, id: u64) -> BoxFuture<'_, String> {
        Box::pin(async move { format!("row-{id}") })
    }
}

async fn load(repo: &dyn Repository) -> String {
    repo.get(7).await
}

#[tokio::main]
async fn main() {
    let repo: Box<dyn Repository> = Box::new(MemoryRepository);
    assert_eq!(load(&*repo).await, "row-7");
}
```

This makes the allocation and type erasure explicit. `async-trait` provides a convenient macro-based version of the same general technique and remains useful when dyn dispatch is required.

## `Send` Is a Return-Future Contract

A native `async fn` in a trait does not let generic callers assume that its returned future is `Send`. This matters when a caller wants to move that future through an API that requires `Send`, such as `tokio::spawn` on a multithreaded runtime.

If the public contract requires a `Send` future, write that contract explicitly with return-position `impl Future`:

```rust
use std::future::Future;

trait Repository: Sync {
    fn get(&self, id: u64) -> impl Future<Output = String> + Send;
}

struct MemoryRepository;

impl Repository for MemoryRepository {
    async fn get(&self, id: u64) -> String {
        format!("row-{id}")
    }
}

fn spawn_load<R>(repo: &'static R) -> tokio::task::JoinHandle<String>
where
    R: Repository + Send + Sync + 'static,
{
    tokio::spawn(async move { repo.get(7).await })
}

#[tokio::main]
async fn main() {
    static REPO: MemoryRepository = MemoryRepository;
    assert_eq!(spawn_load(&REPO).await.unwrap(), "row-7");
}
```

The distinction is “future may be `Send`” versus “the trait promises callers that it is `Send`.” An implementation can happen to produce a `Send` future without the trait exposing that fact to generic callers.

## `trait-variant` Solves the `Send`-Variant Problem, Not Dyn Dispatch

The Rust project’s `trait-variant` crate can generate a second form of a trait whose opaque returned futures carry additional bounds such as `Send`. That is useful when a library wants both local and multithread-capable variants.

It does **not** make those RPITIT/async methods dyn-compatible. A generated `Send` variant still returns an opaque `impl Future`, and Rust 1.98’s dyn-compatibility rules still reject such dispatchable methods.

Do not teach `#[trait_variant::make(...)]` as a boxing or trait-object adapter.

## `async-trait` Is Still Appropriate in Some APIs

Keep or choose `async-trait` when its trade-off is the one you want, for example:

- callers require `dyn Trait` today;
- supporting a Rust version older than 1.75 matters;
- a uniform boxed-future ABI is preferable to exposing RPITIT details;
- migration cost is not justified by the call frequency or allocation profile.

The macro generally boxes the returned future, so allocation-sensitive hot paths should measure the actual impact rather than assuming either representation is free.

## Public-Trait Design

For a public async trait, decide before publishing:

- whether dyn dispatch is part of the intended API;
- whether returned futures must be `Send`;
- whether implementers need both local and `Send` variants;
- whether future callers may need additional bounds that native `async fn` syntax does not expose directly.

These are compatibility questions, not merely syntax choices.

## Practical Guidance

- Prefer native `async fn` for straightforward statically dispatched traits.
- Do not claim native async trait methods are dyn-compatible on Rust 1.98.
- Use explicit `-> impl Future + Send` when the trait must promise a `Send` future.
- Use `trait-variant` for generated bound variants, not as a dyn-dispatch solution.
- Keep `async-trait` or another erased-future design when trait objects are required.
- Benchmark allocation-sensitive paths instead of treating one representation as categorically faster.

## See Also

- [async-async-fn-bounds](./async-async-fn-bounds.md) — Higher-order async bounds
- [anti-type-erasure](./anti-type-erasure.md) — Static versus dynamic dispatch trade-offs
- [async-tokio-runtime](./async-tokio-runtime.md) — Spawn requirements and runtime behavior
