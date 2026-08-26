# num-float-compare

> Use approximate comparison when you mean numerical closeness; use exact equality for exact semantics and `total_cmp` for total ordering

## Why It Matters

Floating-point arithmetic rounds, so mathematically equivalent computations can produce different representable values. That makes exact `==` inappropriate when the intended question is "are these numerical results close enough?"

Exact equality is still correct for exact semantics: sentinels such as `0.0` when both signed zeros are intentionally equivalent, detecting whether an unchanged stored value is exactly equal, or protocols whose specification requires IEEE equality.

## Approximate Numerical Equality

```rust
fn approx_eq(a: f64, b: f64, abs_tol: f64, rel_tol: f64) -> bool {
    let diff = (a - b).abs();
    diff <= abs_tol || diff <= rel_tol * a.abs().max(b.abs())
}

assert!(approx_eq(0.1 + 0.2, 0.3, 1e-15, 1e-12));
```

Choose tolerances from the problem domain; a single hard-coded epsilon is not universally meaningful.

## Exact Equality Can Be Intentional

```rust
fn reciprocal(x: f64) -> Option<f64> {
    if x == 0.0 || x.is_nan() {
        None
    } else {
        Some(1.0 / x)
    }
}
```

Here exact comparison to zero expresses the intended branch condition. Note that `-0.0 == 0.0` is true.

## Total Ordering

`partial_cmp` returns `None` for unordered comparisons involving NaN. Use `total_cmp` when you require a deterministic total order over every IEEE-754 bit pattern:

```rust
fn sort_values(values: &mut [f64]) {
    values.sort_by(f64::total_cmp);
}
```

`total_cmp` follows IEEE total ordering. In particular, NaNs do **not** all sort after finite values: negative NaNs sort below negative infinity, while positive NaNs sort above positive infinity. It also distinguishes `-0.0` from `+0.0` in the total order.

## Key Points

- Do not replace every float `==` mechanically.
- Approximate equality needs domain-appropriate absolute and/or relative tolerances.
- `NaN != NaN` under ordinary IEEE equality.
- Use `total_cmp` when a complete deterministic ordering is required.
- If bitwise identity is what matters, compare `to_bits()` values explicitly.

## See Also

- [num-overflow-explicit](num-overflow-explicit.md) — explicit numeric edge-case handling
- [`f64::total_cmp`](https://doc.rust-lang.org/stable/std/primitive.f64.html#method.total_cmp)
