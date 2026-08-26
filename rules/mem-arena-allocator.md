# mem-arena-allocator

> Use arena allocators for batch allocations

## Why It Matters

Arena allocators (bump allocators) allocate memory from a contiguous region, making allocation extremely fast (just bump a pointer). All allocations are freed at once when the arena is dropped. Perfect for request-scoped or parse-tree allocations. **bumpalo 3.20.3** (May 2026) is the current stable release.

## Bad

```rust
// Many small allocations during parsing
fn parse(input: &str) -> Vec<Node> {
    let mut nodes = Vec::new();
    for token in tokenize(input) {
        nodes.push(Box::new(Node::new(token)));  // Heap alloc per node!
    }
    nodes
}

// Per-request allocations add up
fn handle_request(req: Request) -> Response {
    let headers = parse_headers(&req);      // Allocates
    let body = parse_body(&req);            // Allocates
    let response = generate_response();     // Allocates
    // All freed individually at end
    response
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use bumpalo::Bump;

// All nodes allocated from same arena
fn parse<'a>(input: &str, arena: &'a Bump) -> Vec<&'a Node> {
    let mut nodes = Vec::new();
    for token in tokenize(input) {
        let node = arena.alloc(Node::new(token));  // Fast bump!
        nodes.push(node);
    }
    nodes
}  // Arena freed all at once

// Per-request arena
fn handle_request(req: Request) -> Response {
    let arena = Bump::new();
    
    let headers = parse_headers(&req, &arena);
    let body = parse_body(&req, &arena);
    let response = generate_response(&arena);
    
    // Convert to owned response before arena drops
    response.to_owned()
}  // All request memory freed instantly
```

## Fallible Allocation (bumpalo 3.17+)

```rust
use bumpalo::Bump;

let arena = Bump::new();

// try_alloc returns Result — no panic on OOM
let node: Result<&mut Node, _> = arena.try_alloc(Node::new(token));
if let Ok(node) = node {
    process(node);
}

// try_alloc_with for fallible construction
let node: Result<&mut Node, _> = arena.try_alloc_with(|| Node::new(token));
```

## Thread-Local Scratch Arena Pattern

```rust
use bumpalo::Bump;
use std::cell::RefCell;

thread_local! {
    static SCRATCH: RefCell<Bump> = RefCell::new(Bump::with_capacity(4 * 1024));
}

fn with_scratch<T>(f: impl FnOnce(&Bump) -> T) -> T {
    SCRATCH.with(|scratch| {
        let arena = scratch.borrow();
        let result = f(&arena);
        result
    })
}

fn reset_scratch() {
    SCRATCH.with(|scratch| {
        scratch.borrow_mut().reset();
    });
}

// Usage
fn process_batch(items: &[Item]) -> Vec<Output> {
    with_scratch(|arena| {
        let temp_data: Vec<&TempData> = items
            .iter()
            .map(|item| arena.alloc(compute_temp(item)))
            .collect();
        
        // Use temp_data...
        let result = finalize(&temp_data);
        
        reset_scratch();  // Reuse arena memory
        result
    })
}
```

## Multi-Threaded: bumpalo-herd

For multi-threaded work stealing, use `bumpalo-herd` to avoid thread-local contention:

```rust
use bumpalo_herd::Herd;

let herd = Herd::new(|_| Bump::new());
let work: Vec<_> = (0..4)
    .map(|i| {
        let h = herd.clone();
        std::thread::spawn(move || {
            let member = h.get();
            member.bump().alloc(MyData { id: i });
        })
    })
    .collect();
```

## Bumpalo Collections

```rust
use bumpalo::Bump;
use bumpalo::collections::{Vec, String};

fn process<'a>(arena: &'a Bump, input: &str) -> Vec<'a, String<'a>> {
    let mut results = Vec::new_in(arena);
    
    for word in input.split_whitespace() {
        let mut s = String::new_in(arena);
        s.push_str(word);
        s.push_str("_processed");
        results.push(s);
    }
    
    results  // All allocated in arena
}
```

## allocator_api (Nightly)

On nightly Rust, you can use the `allocator_api` feature for generic allocator-aware containers:

```rust
#![feature(allocator_api)]

use bumpalo::Bump;
use std::boxed::Box;

let arena = Bump::new();

// Generic allocator-aware Box
let val = Box::new_in(42, &arena);

// Works with Vec, Rc, etc. (when stabilized)
```

## Alternative: slotmap for Stable Handles

If you need stable, type-safe handles to arena-allocated data (instead of raw pointers), use `slotmap`:

```rust
use slotmap::{SlotMap, Key};

let mut arena = SlotMap::new();
let handle: Key = arena.insert(MyNode::new());
let node: &MyNode = &arena[handle];  // Stable reference
```

## When to Use Arenas

| Situation | Use Arena? |
|-----------|-----------|
| Parsing (AST nodes) | Yes |
| Request handling | Yes |
| Batch processing | Yes |
| Long-lived data | No |
| Data escaping scope | No (or copy out) |
| Simple programs | Overkill |

## Performance Impact

```rust
// Benchmarks from production systems:
// - Individual allocations: ~25-50ns each
// - Arena bump: ~1-2ns each (20-50x faster)
// - Arena reset: O(1) regardless of allocation count

// Memory overhead:
// - Arena wastes some memory (unused capacity)
// - But eliminates per-allocation metadata overhead
```

## Cargo.toml

```toml
[dependencies]
bumpalo = "3.20"
# For multi-threaded work stealing
bumpalo-herd = "0.1"
# Stable typed handles instead of raw pointers
slotmap = "1.0"
```

## See Also

- [mem-slotmap-arena](mem-slotmap-arena.md) — Stable typed handles with `SlotMap`
- [mem-with-capacity](mem-with-capacity.md) - Pre-allocate when size is known
- [mem-reuse-collections](mem-reuse-collections.md) - Reuse collections with clear()
- [opt-profile-first](perf-profile-first.md) - Profile to verify benefit
