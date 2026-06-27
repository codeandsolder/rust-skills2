# lint-warn-style

**Rule**: `lint-warn-style`

> Enable clippy::style for idiomatic code

## Why It Matters

The `clippy::style` lint group enforces idiomatic Rust patterns. While not bugs, style violations make code harder to read and maintain. Consistent style helps teams work together and makes code easier to review. Edition 2024 introduces new style-related lints and changes the default level of some existing lints.

## Configuration

```rust
// In lib.rs or main.rs
#![warn(clippy::style)]
```

Or in `Cargo.toml`:

```toml
[lints.clippy]
style = "warn"
```

## What It Catches

### Redundant Code

```rust
// WARN: Redundant clone on Copy type
let x = 5;
let y = x.clone();  // Just use: let y = x;

// WARN: Redundant closure
iter.map(|x| foo(x))  // Just use: iter.map(foo)

// WARN: Redundant pattern matching
match result {
    Ok(x) => Ok(x),
    Err(e) => Err(e),
}  // Just return result
```

### Non-Idiomatic Patterns

```rust
// WARN: Should use if let
match option {
    Some(x) => do_something(x),
    None => {},
}
// Better: if let Some(x) = option { do_something(x) }

// WARN: Should use or_else
let value = if option.is_some() {
    option.unwrap()
} else {
    default()
};
// Better: option.unwrap_or_else(default)

// WARN: Collapsible if statements
if condition1 {
    if condition2 {
        do_something();
    }
}
// Better: if condition1 && condition2 { do_something() }
```

### Naming Issues

```rust
// WARN: Function should not start with 'is_' returning non-bool
fn is_valid() -> i32 { 0 }  // Misleading name

// WARN: Method should not be named 'new' without returning Self
impl Foo {
    fn new() -> Bar { Bar }  // Confusing
}
```

## Notable Lints in This Group

| Lint | Better Pattern |
|------|---------------|
| `len_zero` | Use `is_empty()` instead of `len() == 0` |
| `redundant_field_names` | Use shorthand `{ x }` not `{ x: x }` |
| `unused_unit` | Remove `-> ()` and trailing `()` |
| `collapsible_if` | Combine nested ifs with `&&` |
| `single_match` | Use `if let` instead |
| `match_like_matches_macro` | Use `matches!()` macro |
| `needless_return` | Remove explicit `return` at end |
| `question_mark` | Use `?` instead of `match` |

## Edition 2024 Style Lints

### `unused_visibilities` (1.94, warn-by-default)

Catches visibility modifiers (`pub`, `pub(crate)`, etc.) that have no effect:

```rust
// WARN: unused visibility — private items don't need pub(crate)
pub(crate) const _: u32 = 42;  // Remove pub(crate), const _ is already private
pub(crate) fn helper() {}       // Only if used within crate — ok
```

### `irrefutable_let_patterns` (1.95 behavior change)

In Edition 2024, irrefutable `if let` patterns are now more consistently handled:

```rust
// WARN in Edition 2024: irrefutable if let — the pattern always matches
if let x = 5 {  // Just use: let x = 5;
    println!("{x}");
}
```

### `unsafe_op_in_unsafe_fn` (Edition 2024, deny-by-default)

Edition 2024 requires each unsafe operation inside an `unsafe fn` to be wrapped in its own `unsafe {}` block:

```rust
// Edition 2024 — ERROR: unsafe_op_in_unsafe_fn
unsafe fn read(ptr: *const u8) -> u8 {
    *ptr  // Each unsafe op must be in an unsafe block
}
```

## Examples

```rust
// Before (style warnings)
fn process(data: Vec<i32>) -> Option<i32> {
    if data.len() == 0 {
        return None;
    }
    let first = match data.first() {
        Some(x) => x,
        None => return None,
    };
    return Some(*first);
}

// After (idiomatic)
fn process(data: Vec<i32>) -> Option<i32> {
    if data.is_empty() {
        return None;
    }
    let first = data.first()?;
    Some(*first)
}
```

## Selective Allowance

Some style lints may conflict with team preferences:

```rust
// If your team prefers explicit returns
#[allow(clippy::needless_return)]
fn explicit_return() -> i32 {
    return 42;
}
```

## See Also

- [lint-warn-suspicious](./lint-warn-suspicious.md) - Suspicious patterns
- [lint-warn-complexity](./lint-warn-complexity.md) - Complexity warnings
- [lint-rustfmt-check](./lint-rustfmt-check.md) - Formatting checks
