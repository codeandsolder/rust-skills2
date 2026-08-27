# doc-panics-section

> Include `# Panics` section for functions that can panic

## Why It Matters

Panics are exceptional conditions that crash the program (or unwind the stack). Users need to know when a function might panic so they can ensure preconditions are met or avoid the function in contexts where panics are unacceptable (e.g., `no_std`, embedded, FFI).

If a function can panic, document exactly when.

## Bad

```rust
/// Returns the element at the given index.
pub fn get<T>(data: &[T], index: usize) -> &T {
    &data[index]  // Panics if out of bounds - not documented!
}

/// Divides two numbers.
pub fn divide(a: i32, b: i32) -> i32 {
    a / b  // Panics on division by zero - not documented!
}
```

## Good

<!-- rust-check: compile -->
```rust
/// Returns the element at the given index.
///
/// # Panics
///
/// Panics if `index` is out of bounds (i.e., `index >= data.len()`).
///
/// # Examples
///
/// ```
/// let v = vec![1, 2, 3];
/// assert_eq!(get(&v, 1), &2);
/// ```
pub fn get<T>(data: &[T], index: usize) -> &T {
    &data[index]
}

/// Divides two numbers.
///
/// # Panics
///
/// Panics if `divisor` is zero.
///
/// For a non-panicking version, use [`checked_divide`].
pub fn divide(dividend: i32, divisor: i32) -> i32 {
    dividend / divisor
}

/// Divides two numbers, returning `None` if the divisor is zero.
pub fn checked_divide(dividend: i32, divisor: i32) -> Option<i32> {
    if divisor == 0 {
        None
    } else {
        Some(dividend / divisor)
    }
}
```

## Common Panic Conditions

| Operation | Panic Condition |
|-----------|-----------------|
| Index access `[i]` | Index out of bounds |
| Division `/`, `%` | Division by zero |
| `.unwrap()` | `None` or `Err` value |
| `.expect()` | `None` or `Err` value |
| `slice::split_at(mid)` | `mid > len` |
| `Vec::remove(i)` | `i >= len` |
| Overflow (debug) | Integer overflow |

## Pattern: Panic vs Return Error

Document why you chose to panic vs return `Result`:

```rust
/// Creates a new buffer with the given capacity.
///
/// # Panics
///
/// Panics if `capacity` is zero. A buffer must have at least
/// one byte of capacity.
///
/// This panics rather than returning an error because a zero-capacity
/// buffer represents a programming error, not a runtime condition.
pub fn new(capacity: usize) -> Self {
    assert!(capacity > 0, "capacity must be non-zero");
    // ...
}
```

## Pattern: Debug-Only Panics

```rust
/// Adds an item to the collection.
///
/// # Panics
///
/// In debug builds, panics if the collection is at capacity.
/// In release builds, this is a no-op when at capacity.
pub fn push(&mut self, item: T) {
    debug_assert!(self.len < self.capacity, "collection at capacity");
    // ...
}
```

Note: `debug_assert!` only panics in debug builds. Document this
difference so users aren't surprised in release builds.

## Provide Non-Panicking Alternatives

When documenting a panicking function, point to safe alternatives:

```rust
/// # Panics
///
/// Panics if the index is out of bounds.
///
/// For a non-panicking version, use [`get`] which returns `Option<&T>`.
```

## Lints

Enable `clippy::missing_panics_doc` to catch missing `# Panics` sections:

```rust
#![warn(clippy::missing_panics_doc)]
```

This warns on any public function that can panic (via `unwrap`, `expect`,
indexing, `assert!`, etc.) without a `# Panics` section.

## See Also

- [doc-errors-section](./doc-errors-section.md) - Documenting errors
- [doc-safety-section](./doc-safety-section.md) - Documenting unsafe
- [err-result-over-panic](./err-result-over-panic.md) - Preferring Result
