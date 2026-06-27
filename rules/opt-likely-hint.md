# opt-likely-hint

> Use `cold_path()` and `select_unpredictable` for branch hints on stable Rust

## Why It Matters

Modern CPUs predict branches to speculatively execute code. Mispredictions cause pipeline stalls (10-20 cycles). Helping the compiler understand which branches are likely allows it to generate optimal code layout and branch hints, improving performance in hot paths.

## cold_path() — Canonical Stable Branch Hint (Rust 1.95+)

Since Rust 1.95.0, `core::hint::cold_path()` is the canonical stable way to hint branch probabilities:

```rust
use core::hint::cold_path;

fn process(data: &Data) -> i32 {
    if data.is_corrupted() {
        cold_path();  // Hint: this path is unlikely
        return handle_corruption(data);
    }
    
    if data.is_cached() {
        return fast_cached_path(data);
    }
    cold_path();  // Hint: uncached path is unlikely too
    
    slow_uncached_path(data)
}
```

## Stable likely()/unlikely() via cold_path()

```rust
use core::hint::cold_path;

/// Stable likely() — no nightly or external crate needed.
#[inline(always)]
pub const fn likely(b: bool) -> bool {
    if !b { cold_path(); }
    b
}

/// Stable unlikely() — no nightly or external crate needed.
#[inline(always)]
pub const fn unlikely(b: bool) -> bool {
    if b { cold_path(); }
    b
}

// Usage
fn check(value: i32) -> bool {
    if unlikely(value < 0) {
        handle_negative()
    } else if likely(value < 1000) {
        handle_common()
    } else {
        handle_large()
    }
}
```

## Loop Optimization

```rust
fn search(data: &[i32], target: i32) -> Option<usize> {
    for (i, &item) in data.iter().enumerate() {
        cold_path();  // Assume most iterations don't find the target
        if item == target {
            return Some(i);
        }
    }
    None
}
```

## select_unpredictable() — Branchless Conditional (Rust 1.88+)

For truly unpredictable branches (binary search midpoints, hash table probing), use `core::hint::select_unpredictable` to generate branchless `cmov`/`csel` instructions:

```rust
use core::hint::select_unpredictable;

fn binary_search(data: &[i32], target: i32) -> Option<usize> {
    let mut base = 0usize;
    let mut size = data.len();

    while size > 1 {
        let half = size / 2;
        // Branchless mid-point selection — no branch misprediction
        base = select_unpredictable(
            data[base + half] < target,
            base + half,
            base,
        );
        size -= half;
    }

    if size > 0 && data[base] == target { Some(base) } else { None }
}

// Works with any comparable type
fn clamp_unpredictable(x: i32, lo: i32, hi: i32) -> i32 {
    select_unpredictable(x < lo, lo, select_unpredictable(x > hi, hi, x))
}
```

### When to Use

| Use select_unpredictable | Don't use it |
|--------------------------|--------------|
| Truly unpredictable branches (binary search, hash probes) | Highly predictable branches (error checks, bounds checks) |
| Performance-critical hot paths | Cold paths or infrequent code |
| After profiling confirms mispredictions | Without profiling data |

## Code Structure Hints (Stable, always available)

```rust
// Pattern 1: Early returns for unlikely cases
fn process(data: Option<&Data>) -> i32 {
    // Compiler assumes early return is "unlikely"
    let data = match data {
        None => return 0,  // Unlikely
        Some(d) => d,
    };
    
    // Hot path continues here
    complex_processing(data)
}

// Pattern 2: if-else ordering
fn calculate(x: i32) -> i32 {
    if x >= 0 {
        // Put likely case in "if" branch
        x * 2
    } else {
        // Unlikely case in "else"
        handle_negative(x)
    }
}

// Pattern 3: Cold function extraction
fn hot_path(data: &[u8]) -> Result<(), Error> {
    if data.is_empty() {
        return cold_empty_error();  // Extracted = unlikely
    }
    
    process_fast(data)
}

#[cold]
fn cold_empty_error() -> Result<(), Error> {
    Err(Error::EmptyInput)
}
```

## Match Arm Ordering

```rust
// Put most common variants first
fn process_message(msg: Message) {
    match msg {
        // Most common - listed first
        Message::Data(d) => handle_data(d),
        Message::Heartbeat => (), // Second most common
        
        // Rare cases last
        Message::Error(e) => handle_error(e),
        Message::Shutdown => shutdown(),
    }
}
```

## Benchmark-Driven Hints

```rust
// Profile first to know which branches are actually likely!
fn speculative(x: i32) -> i32 {
    // DON'T GUESS - measure with profiling
    // perf record / perf report
    // cargo flamegraph
    
    if x > threshold {  // Is this actually common?
        path_a(x)
    } else {
        path_b(x)
    }
}
```

## Evolution of Branch Hints in Rust

| Era | Method | Since |
|-----|--------|-------|
| Rust 1.0 | `#[cold]` + `#[inline(never)]` | Always stable |
| Nightly | `core_intrinsics::likely`/`unlikely` | Nightly only |
| External crate | `likely-stable` crate | Third-party |
| Rust 1.88.0 | `core::hint::select_unpredictable` | Stable |
| Rust 1.95.0 | `core::hint::cold_path()` | Stable |

## See Also

- [opt-cold-unlikely](./opt-cold-unlikely.md) - #[cold] for unlikely functions
- [opt-cold-path](./opt-cold-path.md) - Using cold_path() for inline path marking
- [opt-select-unpredictable](./opt-select-unpredictable.md) - Branchless conditional moves
- [perf-profile-first](./perf-profile-first.md) - Profile to know what's likely
