# lint-warn-suspicious

**Rule**: `lint-warn-suspicious`

> Enable clippy::suspicious for likely bugs

## Why It Matters

The `clippy::suspicious` lint group catches code patterns that are syntactically valid but almost always wrong. These are potential bugs that deserve investigation. Enabling this group as a warning helps catch mistakes early. Several related lints have also been uplifted to rustc.

## Configuration

```toml
# Cargo.toml — canonical configuration
[lints.clippy]
suspicious = "warn"
```

Or stricter:

```toml
[lints.clippy]
suspicious = { level = "deny", priority = -1 }
```

## What It Catches

### Suspicious Arithmetic

```rust
// WARN: Suspicious use of + in a << expression
let bits = 1 << 4 + 1;  // Probably meant (1 << 4) + 1 or 1 << (4 + 1)

// WARN: Suspicious use of | in a + expression
let value = x | 1 + y;  // Probably meant (x | 1) + y or x | (1 + y)
```

### Suspicious Comparisons

```rust
// WARN: Almost swapped operands in a comparison
if 5 < x && x < 3 { }  // Impossible condition

// WARN: Suspicious assignment in a condition
if (x = 5) { }  // Probably meant x == 5
```

### Suspicious Method Calls

```rust
// WARN: Suspicious map usage
let _: Vec<_> = vec.iter().map(|x| { 
    println!("{}", x);  // Side effect in map
    x
}).collect();  // Use for_each instead

// WARN: Suspicious string formatting
let s = format!("{}", format!("{}", x));  // Redundant nested format
```

### Suspicious Casts

```rust
// WARN: Suspicious use of not on a bool
let inverted = !x as i32;  // Did you mean (!x) as i32 or !(x as i32)?

// WARN: Cast of float to int may lose precision
let n = 3.14_f64 as i32;  // May want .round() first
```

## Notable Lints in This Group

| Lint | Description |
|------|-------------|
| `suspicious_arithmetic_impl` | Unusual operator in arithmetic trait |
| `suspicious_assignment_formatting` | Looks like typo in assignment |
| `suspicious_else_formatting` | Else on wrong line |
| `suspicious_map` | Map with side effects |
| `suspicious_op_assign_impl` | Unusual op-assign implementation |
| `suspicious_splitn` | splitn that can't produce n parts |
| `suspicious_unary_op_formatting` | Confusing unary operator spacing |

## Example Catches

```rust
// Caught: Suspicious double negation
let value = --x;  // In Rust, this is -(-x), not pre-decrement

// Caught: Suspicious modulo
let remainder = x % 1;  // Always 0 for integers

// Caught: Suspicious else formatting
if condition {
    do_something();
}
else {  // Weird formatting, might be a mistake
    do_other();
}
```

## Uplifted Rustc Lints (Suspicious Category)

Several rustc lints complement the `clippy::suspicious` group. Configure them under `[lints.rust]`:

```toml
[lints.rust]
semicolon_in_expressions_from_macros = "deny"  # 1.91
dangerous_implicit_autorefs           = "deny"  # 1.89
integer_to_ptr_transmutes             = "warn"  # 1.91
const_item_interior_mutations         = "warn"  # 1.93
function_casts_as_integer             = "warn"  # 1.93
```

| Lint | Since | Level | What It Catches |
|------|-------|-------|-----------------|
| `semicolon_in_expressions_from_macros` | 1.91 | deny | Semicolon in macro expression position |
| `dangerous_implicit_autorefs` | 1.89 | deny | Unexpected implicit autoref creates surprising borrows |
| `integer_to_ptr_transmutes` | 1.91 | warn | Transmuting integer to pointer |
| `const_item_interior_mutations` | 1.93 | warn | Mutable reference to const item |
| `function_casts_as_integer` | 1.93 | warn | Casting function pointer to integer |

## When to Allow

Rarely. If you need to suppress, document why:

```rust
#[allow(clippy::suspicious_arithmetic_impl)]
impl Mul for Matrix {
    // Custom matrix multiplication using + for reduction step
    fn mul(self, rhs: Self) -> Self::Output {
        // ...
    }
}
```

## See Also

- [lint-deny-correctness](./lint-deny-correctness.md) — Deny definite bugs
- [lint-warn-style](./lint-warn-style.md) — Style warnings
- [lint-warn-complexity](./lint-warn-complexity.md) — Complexity warnings
- [lint-uplifted](./lint-uplifted.md) — Tracking clippy lints uplifted to rustc
