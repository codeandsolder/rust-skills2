# mem-arena-allocator

> Use bump arenas when many values share one lifetime and bulk deallocation is more useful than individual destruction

## Why It Matters

A bump arena allocates values from chunks and advances an allocation cursor. That can make repeated small allocations cheap and lets the arena reclaim its storage in bulk. The model is especially attractive for parse trees, temporary query state, request-scoped scratch data, and other workloads where many allocations naturally die together.

The trade-off is just as important: values allocated directly with `bumpalo::Bump` do **not** have their `Drop` implementations run when the arena is reset or dropped. If an arena value owns a file, socket, mutex guard, heap allocation, mmap, or another resource whose destructor matters, blindly placing it in the arena can leak or delay that resource.

Use arenas because the lifetime model fits—not because “arena allocation is always faster.” Measure the real workload.

## Basic Arena Allocation

```rust
use bumpalo::Bump;

#[derive(Debug, PartialEq)]
struct Node {
    value: i32,
}

fn build_nodes(arena: &Bump) -> Vec<&Node> {
    (0..4)
        .map(|value| arena.alloc(Node { value }) as &Node)
        .collect()
}

fn main() {
    let arena = Bump::new();
    let nodes = build_nodes(&arena);
    assert_eq!(nodes[2].value, 2);
}
```

The references cannot outlive `arena`, so the borrow checker prevents them from escaping the arena's lifetime.

## The Critical Destructor Caveat

Directly bump-allocated values are not individually dropped during arena teardown. For plain data that needs no destructor, this is often exactly what you want. For resource-owning values, it can be wrong.

```rust
use bumpalo::Bump;

#[derive(Debug)]
struct PlainNode {
    id: u32,
    weight: u32,
}

fn main() {
    let arena = Bump::new();
    let node = arena.alloc(PlainNode { id: 1, weight: 7 });
    assert_eq!(node.weight, 7);
}
```

A plain-data node has no destructor-dependent cleanup. By contrast, putting a `String`, `Vec`, file handle, or other resource-owning object directly in the bump means its own destructor will not run automatically when the bump is cleared.

If destructors must run, choose a representation that explicitly manages them. `bumpalo` offers allocator-aware owned/collection types behind crate features, and manual cleanup is also possible, but those choices should be reviewed carefully rather than assumed.

## `reset()` Reuses Arena Storage

`Bump::reset` takes `&mut self`, invalidating outstanding arena references before the reset can occur:

```rust
use bumpalo::Bump;

fn main() {
    let mut arena = Bump::new();

    {
        let value = arena.alloc(123_u32);
        assert_eq!(*value, 123);
    }

    arena.reset();

    let next = arena.alloc(456_u32);
    assert_eq!(*next, 456);
}
```

Resetting bulk-reclaims bump allocations and keeps storage available for reuse according to the allocator's implementation. Do not describe it as a universal constant-time operation independent of chunk state: an implementation may release excess chunks while retaining storage for reuse.

The destructor caveat still applies to values allocated before a reset.

## Fallible Allocation Versus Fallible Construction

Current `bumpalo` distinguishes allocation failure from initializer failure:

- `try_alloc(value)` / `try_alloc_with(|| value)` make the **allocation** fallible;
- `alloc_try_with(|| Result<...>)` / `try_alloc_try_with(...)` are the APIs for a **fallible initializer**.

Do not call `try_alloc_with` “fallible construction”: its closure itself returns the value, not a `Result` from construction.

When out-of-memory behavior matters, use the relevant `try_` APIs and propagate their allocation errors instead of assuming every bump allocation can succeed.

## Per-Request Arenas

A useful shape is to create the arena outside the work that borrows from it, then convert only the final escaping value into ordinary owned data:

```rust
use bumpalo::Bump;

fn summarize(input: &str) -> String {
    let arena = Bump::new();
    let words: Vec<&str> = input
        .split_whitespace()
        .map(|word| arena.alloc_str(word) as &str)
        .collect();

    words.join("|")
}

fn main() {
    assert_eq!(summarize("one two three"), "one|two|three");
}
```

The returned `String` owns its memory independently; the temporary word copies can disappear with the arena.

If most inputs are already borrowed strings and do not need copying, an arena may provide no benefit here—the example demonstrates the lifetime pattern, not a recommendation to arena-copy every `&str`.

## Threading

A `bumpalo::Bump` can be moved between threads, but it is not a shared concurrent allocator. Do not concurrently allocate through one shared `&Bump` from multiple threads. Common designs use one arena per worker/request or another allocator explicitly designed for concurrent access.

## Stable Handles Are a Different Problem

`slotmap` is not a bump allocator. It is useful when you want stable, generation-checked keys into a collection whose entries may be inserted and removed:

```rust
use slotmap::{DefaultKey, SlotMap};

#[derive(Debug)]
struct Node {
    value: i32,
}

fn main() {
    let mut nodes = SlotMap::new();
    let key: DefaultKey = nodes.insert(Node { value: 42 });

    assert_eq!(nodes[key].value, 42);
    nodes.remove(key);
    assert!(nodes.get(key).is_none());
}
```

The key remains a small handle and stale generations are rejected after removal. This provides stable **keys**, not stable Rust references, and it does not give bump-allocation semantics.

Use a slot map when identity/handles are the requirement; use a bump arena when shared lifetime and bulk allocation/deallocation are the requirement.

## When Arenas Fit

Arenas are worth considering when:

- many allocations naturally share one lifetime;
- values are mostly plain data or their destruction is otherwise managed;
- per-object deallocation is unnecessary;
- profiling shows allocator traffic or locality is important;
- the lifetime boundary can be expressed clearly in the type/borrow structure.

Prefer ordinary `Vec`, `Box`, `String`, ownership, or another collection when individual destruction, independent lifetimes, or simple code matters more.

## Performance Guidance

Do not bake numbers such as “arena allocation is 20–50× faster” or “1–2 ns per allocation” into a general rule. Results depend on allocator, element size/alignment, chunk growth, cache state, compiler options, and whether ordinary allocations were optimized away or pooled elsewhere.

Benchmark the operation that matters: parse throughput, request latency, allocation count, resident memory, or cache behavior—not an isolated synthetic allocation unless that is actually the bottleneck.

## Practical Guidance

- Start from a shared-lifetime problem, not from a desire to replace every `Box`.
- Remember that direct bump allocations skip `Drop` on reset/arena destruction.
- Use `reset()` only after all arena borrows are gone.
- Distinguish fallible allocation APIs from fallible initializer APIs.
- Do not share one `Bump` concurrently as though it were a synchronized allocator.
- Treat `slotmap` and arenas as different tools: stable keys versus bulk lifetime allocation.
- Measure before claiming a performance win.

## See Also

- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocate when size is known
- [mem-reuse-collections](./mem-reuse-collections.md) - Reuse collection allocations
- [mem-slotmap-arena](./mem-slotmap-arena.md) - Generation-checked stable keys
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
