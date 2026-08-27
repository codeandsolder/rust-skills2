# opt-cold-unlikely

> Mark unlikely code paths with `#[cold]` to help compiler optimization

## Why It Matters

The `#[cold]` attribute tells the compiler that a function is rarely called. The compiler uses this to optimize code layout—keeping cold code away from hot code improves instruction cache utilization. Combined with branch layout optimization, this can measurably improve performance.

## Bad

<!-- rust-check: fragment; reason=optimization anti-pattern uses surrounding request and error types -->
```rust
// All branches treated equally
fn validate(input: &str) -> Result<Data, ValidationError> {
    if input.is_empty() {
        return Err(ValidationError::Empty);  // Rare
    }
    
    if input.len() > 1000 {
        return Err(ValidationError::TooLong);  // Rare  
    }
    
    if !input.is_ascii() {
        return Err(ValidationError::NonAscii);  // Rare
    }
    
    // This is the common case
    Ok(parse_data(input))
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
fn validate(input: &str) -> Result<Data, ValidationError> {
    if input.is_empty() {
        return cold_empty_error();
    }
    
    if input.len() > 1000 {
        return cold_too_long_error();
    }
    
    if !input.is_ascii() {
        return cold_non_ascii_error();
    }
    
    Ok(parse_data(input))
}

#[cold]
fn cold_empty_error() -> Result<Data, ValidationError> {
    Err(ValidationError::Empty)
}

#[cold]
fn cold_too_long_error() -> Result<Data, ValidationError> {
    Err(ValidationError::TooLong)
}

#[cold]
fn cold_non_ascii_error() -> Result<Data, ValidationError> {
    Err(ValidationError::NonAscii)
}
```

## What #[cold] Does

1. **Code placement**: Cold functions are placed in separate code sections, away from hot code
2. **Branch prediction**: Compiler generates branch hints favoring the non-cold path
3. **Inlining decisions**: Cold functions are not inlined into hot paths
4. **Optimization budget**: Compiler spends less effort optimizing cold code

## Common Cold Patterns

```rust
// Error handling
#[cold]
fn handle_error<E: std::fmt::Display>(e: E) -> ! {
    eprintln!("Fatal error: {}", e);
    std::process::exit(1);
}

// Logging rare events
#[cold]
fn log_rare_event(event: &Event) {
    log::warn!("Rare event occurred: {:?}", event);
}

// Fallback paths
#[cold]
fn slow_fallback(data: &Data) -> Output {
    // This path should rarely be taken
    compute_slowly(data)
}

// Panic handlers
#[cold]
fn panic_invalid_state(state: &State) -> ! {
    panic!("Invalid state: {:?}", state);
}
```

## Assertions and Invariants

```rust
fn get_unchecked(&self, index: usize) -> &T {
    if index >= self.len {
        cold_bounds_panic(index, self.len);
    }
    unsafe { &*self.ptr.add(index) }
}

#[cold]
#[inline(never)]
fn cold_bounds_panic(index: usize, len: usize) -> ! {
    panic!("index out of bounds: the len is {} but the index is {}", len, index);
}
```

## Combining with #[inline(never)]

```rust
// Usually combine both for maximum effect
#[cold]
#[inline(never)]
fn error_path() -> Error {
    // Complex error construction stays out of hot code
    Error {
        backtrace: Backtrace::capture(),
        context: gather_context(),
    }
}
```

## cold_path() — Stable Branch Hint (Rust 1.95+)

Since Rust 1.95.0, `core::hint::cold_path()` provides a stable, inline-friendly way to mark code paths as unlikely, without extracting code into separate functions:

```rust
use core::hint::cold_path;

fn validate(input: &str) -> Result<Data, ValidationError> {
    if input.is_empty() {
        cold_path();  // Hint: this path is unlikely
        return Err(ValidationError::Empty);
    }
    
    if input.len() > 1000 {
        cold_path();
        return Err(ValidationError::TooLong);
    }
    
    Ok(parse_data(input))
}
```

### Implementing likely/unlikely with cold_path()

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
fn process(data: &Data) -> i32 {
    if unlikely(data.is_corrupted()) {
        return handle_corruption(data);
    }
    fast_process(data)
}
```

### cold_path() vs #[cold]

| Aspect | `#[cold]` | `cold_path()` |
|--------|-----------|---------------|
| Scope | Function-level | Inline -- within any block |
| Inlining | Prevents inlining | Allows inlining |
| Use case | Large cold functions | Small cold branches in hot code |
| Since | Rust 1.0 | Rust 1.95.0 |

Use `#[cold]` for extracted functions, `cold_path()` for inline hints without extraction.

## Measuring Impact

```rust
// Check code layout with objdump
// objdump -d target/release/binary | less

// Look for .cold sections
// nm target/release/binary | grep cold

// Profile to verify improvement
// perf stat -e cache-misses,cache-references ./binary
```

## See Also

- [opt-inline-never-cold](./opt-inline-never-cold.md) - Combining with inline(never)
- [opt-likely-hint](./opt-likely-hint.md) - Branch prediction hints
- [opt-cold-path](./opt-cold-path.md) - Using cold_path() for inline path marking
- [err-result-over-panic](./err-result-over-panic.md) - Error handling
