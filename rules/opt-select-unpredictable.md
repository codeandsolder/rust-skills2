# opt-select-unpredictable

> Use `core::hint::select_unpredictable()` for branchless conditional moves (Rust 1.88+)

## Why It Matters

Branch mispredictions cost 10-20 cycles each on modern CPUs. For truly unpredictable branches (binary search midpoints, hash table probing, SIMD-style selections), `select_unpredictable()` generates branchless `cmov`/`csel` instructions that execute in constant time regardless of input data — eliminating misprediction penalties.

## Bad

```rust
// Unpredictable branch — frequent mispredictions
fn midpoint(data: &[i32], target: i32) -> usize {
    let mut base = 0;
    let mut size = data.len();
    
    while size > 1 {
        let half = size / 2;
        // This branch is unpredictable — data-dependent
        if data[base + half] < target {
            base = base + half;  // Mispredictions stall the pipeline
        }
        size -= half;
    }
    base
}
```

## Good

```rust
use core::hint::select_unpredictable;

fn midpoint(data: &[i32], target: i32) -> usize {
    let mut base = 0;
    let mut size = data.len();
    
    while size > 1 {
        let half = size / 2;
        // Branchless! Compiler generates cmov/csel
        base = select_unpredictable(
            data[base + half] < target,  // Condition
            base + half,                  // Value if true
            base,                         // Value if false
        );
        size -= half;
    }
    base
}
```

## How It Works

`select_unpredictable(cond, a, b)` tells the compiler:
- The result of `cond` is unpredictable — don't try to predict it
- Generate a conditional move (`cmov` on x86, `csel` on ARM) instead of a branch
- Both `a` and `b` are evaluated (no short-circuiting), so avoid expensive computations

## Common Use Cases

```rust
use core::hint::select_unpredictable;

// 1. Binary search midpoint
fn binary_search(data: &[i32], target: i32) -> Option<usize> {
    let mut base = 0usize;
    let mut size = data.len();
    
    while size > 1 {
        let half = size / 2;
        base = select_unpredictable(
            data[base + half] < target,
            base + half,
            base,
        );
        size -= half;
    }
    
    if size > 0 && data[base] == target { Some(base) } else { None }
}

// 2. Hash table probing
fn probe(hash: u64, slots: &[(u64, Value)]) -> Option<Value> {
    let mut idx = (hash as usize) % slots.len();
    for _ in 0..slots.len() {
        let found = slots[idx].0 == hash;
        if found {
            return Some(slots[idx].1.clone());
        }
        idx = select_unpredictable(
            idx + 1 >= slots.len(),
            0,
            idx + 1,
        );
    }
    None
}

// 3. Clamping / bounds checks (branchless)
fn clamp(value: i32, min: i32, max: i32) -> i32 {
    select_unpredictable(
        value < min,
        min,
        select_unpredictable(value > max, max, value),
    )
}

// 4. Conditional dispatch (constant-time)
fn select_dispatch(cond: bool, fast: fn(), slow: fn()) {
    // For function pointers, not closures
    let selected = select_unpredictable(cond, fast as usize, slow as usize);
    let f: fn() = unsafe { std::mem::transmute(selected) };
    f();
}
```

## When NOT to Use

```rust
use core::hint::select_unpredictable;

// ❌ Predictable branches — let the compiler optimize normally
fn error_check(data: &[u8]) -> Result<(), Error> {
    // This branch is almost never taken — normal prediction works fine
    if data.is_empty() {
        return Err(Error::Empty);
    }
    Ok(())
}

// ❌ Expensive operands — both arms are always evaluated
fn expensive_select(x: i32) -> i32 {
    // Both heavy_compute(x) and light_compute(x) execute every time!
    select_unpredictable(
        x < 0,
        heavy_compute(x),   // Always runs
        light_compute(x),   // Always runs
    )
}

// ❌ Cold/infrequent paths — overhead not worth it
fn rarely_called() {
    // Not performance-sensitive; branch overhead is negligible
    if some_condition() {
        do_something();
    }
}
```

## Performance Comparison

| Aspect | Branch (`if/else`) | `select_unpredictable()` |
|--------|-------------------|--------------------------|
| Predictable branches | ✅ Fast (0-2 cycle mispredict) | ⚠️ Slower (evaluates both arms) |
| Unpredictable branches | ❌ Slow (10-20 cycle mispredict) | ✅ Fast (constant time) |
| Code size | Smaller (one path) | Larger (both paths inlined) |
| When to use | Most branches | After profiling shows mispredictions |

## Verifying Branchless Code

```bash
# Check that select_unpredictable generates cmov (x86) or csel (ARM)
cargo show-asm --rust --release my_crate::hot_function | grep -E 'cmov|csel|cset'
```

If you see `je`/`jne`/`b.cc` instead of `cmov`/`csel`, the compiler didn't honor the hint.

## See Also

- [opt-likely-hint](./opt-likely-hint.md) - Branch hinting with cold_path()
- [opt-cold-path](./opt-cold-path.md) - Marking unlikely inline paths
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
