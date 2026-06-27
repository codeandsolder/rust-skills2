# mem-hotpath-profile

> Profile memory before optimizing

**Rule**: `mem-hotpath-profile`

## Why It Matters

Before reaching for compact strings, arena allocators, or exotic collection types, **measure first**. Memory optimization without profiling is guesswork — you might optimize the wrong allocation, or introduce complexity for zero benefit. Profile-guided memory optimization follows the same principle as `perf-profile-first`: understand where the memory goes before rearranging it.

## The Wrong Way

```rust
// ❌ Reaching for exotic types before measuring
struct Data {
    tags: ThinVec<EcoString>,           // Complex, but is it needed?
    metadata: SlotMap<Key, Metadata>,    // Overkill for 10 items
}

// The developer spent 2 hours optimizing, but 99% of memory
// was actually in a different struct entirely.
```

## Tools

### dhat — Heap Profiler

`dhat` (Dynamic Heap Analysis Tool) replaces the global allocator and records every allocation:

```rust
// In your binary (not library):
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    let _profiler = dhat::Profiler::new_heap();
    
    // Run your code...
    heavy_allocation_work();
    
    // Profiler writes a JSON file on drop
    // Visualize with: https://nnethercote.github.io/dh_view/dh_view.html
}

// To use dhat:
// [dev-dependencies]
// dhat = "0.3"
//
// [profile.dev]
// debug = true  (needed for stack traces)
```

### hotpath-rs — Async-Aware Memory Profiler

`hotpath-rs` profiles allocations with async-aware stack traces:

```rust
// https://hotpath.rs/
// cargo add --dev hotpath

use hotpath::HotPath;

#[hotpath::test]
async fn my_async_test() {
    // Profile allocations in async context
    let result = some_async_fn().await;
    assert!(HotPath::current().total_allocations() < 1000);
}

// Or wrap a block:
let guard = HotPath::record();
do_work();
let report = guard.stop();
println!("{}", report);
```

### heaptrack (Linux)

For more fine-grained analysis:

```bash
# Install: apt install heaptrack
heaptrack ./your-binary
heaptrack_gui heaptrack.12345.gz
```

## Profile-Guided Workflow

```text
1. Profile memory (dhat / hotpath / heaptrack)
2. Identify top allocation sites
3. Check if they're on a hot path (weight > 5%)
4. Apply targeted optimization
5. Re-profile to verify improvement
6. If regression, roll back
```

## Spotting False Targets

```rust
// ❌ Common mistake: optimizing the wrong thing

// This looks wasteful but might be cold:
fn parse_config(path: &str) -> Config {
    let contents = std::fs::read_to_string(path).unwrap();
    serde_json::from_str(&contents).unwrap()
}
// Called once at startup — not worth optimizing.

// This might be the real offender:
fn process_packet(buf: &[u8]) {
    for chunk in buf.chunks(64) {
        let owned = chunk.to_vec();  // Called millions of times
        process(owned);
    }
}
```

## Benchmark Integration

```rust
// Combine criterion benchmarks with dhat for regression testing

#[cfg(test)]
mod tests {
    use dhat::{Alloc, Profiler};
    
    #[test]
    fn test_allocation_count() {
        let _profiler = Profiler::new_heap();
        
        // Run the function
        let result = my_function();
        
        // Check allocation stats via dhat JSON output
        // (Requires parsing the dhat-heap.json file)
    }
}
```

## See Also

- [perf-profile-first](perf-profile-first.md) — Profile before optimizing (general)
- [mem-assert-type-size](mem-assert-type-size.md) — Static size assertions
- [mem-compact-string](mem-compact-string.md) — When to consider compact strings
- [mem-arena-allocator](mem-arena-allocator.md) — Arena allocators (profile first!)
