# opt-cold-path

> Use `core::hint::cold_path()` to mark unlikely inline paths (Rust 1.95+)

## Why It Matters

`cold_path()` is the canonical stable way to hint that a code path is unlikely without extracting code into a separate function. It tells the compiler to optimize the surrounding code for the case where this path is NOT taken, improving branch layout and instruction cache utilization. Unlike `#[cold]`, it works inline — no function extraction needed.

## Bad

```rust
// Extract cold code just to add #[cold] — boilerplate
fn process_value(x: i32) -> i32 {
    if x < 0 {
        return handle_negative(x);  // Must extract
    }
    x * 2
}

#[cold]
fn handle_negative(x: i32) -> i32 {
    log::error!("Negative: {}", x);
    0
}
```

## Good

```rust
use core::hint::cold_path;

fn process_value(x: i32) -> i32 {
    if x < 0 {
        cold_path();  // Inline hint — no extraction needed
        log::error!("Negative: {}", x);
        return 0;
    }
    x * 2
}
```

## Implementing stable likely/unlikely

```rust
use core::hint::cold_path;

/// Stable likely() — no nightly, no external crates.
#[inline(always)]
pub const fn likely(b: bool) -> bool {
    if !b { cold_path(); }
    b
}

/// Stable unlikely() — no nightly, no external crates.
#[inline(always)]
pub const fn unlikely(b: bool) -> bool {
    if b { cold_path(); }
    b
}

// Usage
fn search(data: &[i32], target: i32) -> Option<usize> {
    for (i, &val) in data.iter().enumerate() {
        if likely(val == target) {
            return Some(i);
        }
    }
    None
}
```

## When to Use cold_path() vs #[cold]

| Scenario | Use |
|----------|-----|
| Small unlikely branch (inline) | `cold_path()` |
| Large cold function (> ~10 lines) | `#[cold]` + extraction |
| Both inline hint and extraction | `cold_path()` + `#[cold]` on extracted function |
| In hot loop, branch that's almost never taken | `cold_path()` |

## Common Patterns

```rust
use core::hint::cold_path;

// Guard clauses
fn read_file(path: &str) -> Result<String, Error> {
    if path.is_empty() {
        cold_path();
        return Err(Error::EmptyPath);
    }
    std::fs::read_to_string(path)
}

// Expected vs exceptional flow
fn parse_config(text: &str) -> Config {
    if let Some(parsed) = try_fast_parse(text) {
        parsed
    } else {
        cold_path();
        slow_fallback_parse(text)
    }
}

// Debug assertions in hot code
fn hot_process(data: &[u8]) {
    debug_assert!({
        let ok = data.len() > 4;
        if !ok { cold_path(); }
        ok
    });
    // ... hot path
}

// Loop termination conditions
fn find_first(data: &[i32], pred: impl Fn(i32) -> bool) -> Option<usize> {
    for (i, &val) in data.iter().enumerate() {
        if pred(val) {
            cold_path();  // Found — usually early exit
            return Some(i);
        }
    }
    None
}
```

## cold_path() in Fallback Dispatch

```rust
use core::hint::cold_path;

fn process_data(data: &[f32]) -> f32 {
    // Try fast path first
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("avx2") {
        return avx2_process(data);  // Likely: fast path
    }
    
    cold_path();  // Unlikely: fallback
    generic_process(data)
}
```

## Performance Impact

`cold_path()` influences two compiler behaviors:
1. **Code layout**: Cold code is placed in separate `.cold` sections, away from hot code
2. **Branch probabilities**: The compiler weights branches as unlikely, affecting subsequent optimization decisions

Typical impact: 1-5% improvement in hot loops with well-chosen hints.

## See Also

- [opt-cold-unlikely](./opt-cold-unlikely.md) - #[cold] for function-level path marking
- [opt-likely-hint](./opt-likely-hint.md) - Comprehensive branch hint guide
- [opt-select-unpredictable](./opt-select-unpredictable.md) - Branchless conditional moves
