# num-float-compare

> Use approximate comparison when you mean numerical closeness; use exact equality for exact semantics and `total_cmp` for total ordering

## Why It Matters

Floating-point arithmetic rounds, so mathematically equivalent computations can produce different representable values. That makes exact `==` inappropriate when the intended question is "are these numerical results close enough?"

Exact equality is still correct for exact semantics: sentinels such as `0.0` when both signed zeros are intentionally equivalent, detecting whether an unchanged stored value is exactly equal, or protocols whose specification requires IEEE equality.

Rust 1.98 adds a second, separate semantic choice: `f32`/`f64` algebraic arithmetic methods let the compiler use algebraic identities that ordinary floating-point operators deliberately cannot assume. This can enable reassociation and vectorization, but results are intentionally not reproducible in the same way as ordinary evaluation order.

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

## Rust 1.98+: Algebraic Arithmetic Is an Explicit Optimization Contract

Ordinary operators preserve Rust's normal floating-point evaluation semantics. Rust 1.98's `algebraic_add`, `algebraic_sub`, `algebraic_mul`, `algebraic_div`, and `algebraic_rem` instead tell the optimizer it may use algebraic identities that are not generally valid for finite-precision floating point.

For example:

```rust
fn sum4(a: f64, b: f64, c: f64, d: f64) -> f64 {
    a.algebraic_add(b)
        .algebraic_add(c)
        .algebraic_add(d)
}
```

The compiler may reassociate such a chain rather than preserving the parsed left-to-right grouping. This can enable parallel evaluation or loop vectorization. The exact optimization set is deliberately unspecified and may change between compiler versions or targets.

Use algebraic operations only when all of the following are true:

- profiling shows floating-point arithmetic is a meaningful hot path;
- the numerical error budget tolerates reassociation or similar transformations;
- bit-for-bit reproducibility across compiler versions, optimization choices, or targets is not required;
- tests validate application-level error bounds or invariants rather than one exact rounding history.

Do **not** mechanically replace `+`, `-`, `*`, `/`, or `%` with algebraic methods. Ordinary operators remain the default when exact Rust evaluation semantics matter. The algebraic methods do not introduce undefined behavior; they deliberately widen the set of valid numerical results the optimizer may produce.

For reductions, it is often better to pair algebraic arithmetic with an explicit numerical strategy—such as pairwise summation or compensated summation—when accuracy matters. Faster reassociation and better numerical stability are different goals.

## Key Points

- Do not replace every float `==` mechanically.
- Approximate equality needs domain-appropriate absolute and/or relative tolerances.
- `NaN != NaN` under ordinary IEEE equality.
- Use `total_cmp` when a complete deterministic ordering is required.
- If bitwise identity is what matters, compare `to_bits()` values explicitly.
- On Rust 1.98+, treat `algebraic_*` operations as an opt-in relaxed-arithmetic contract, not as a universally faster spelling of ordinary operators.
- Benchmark algebraic arithmetic on representative targets and test numerical error bounds before adopting it.

## See Also

- [num-overflow-explicit](num-overflow-explicit.md) — explicit numeric edge-case handling
- [perf-profile-first](perf-profile-first.md) — measure before optimizing
- [opt-simd-portable](opt-simd-portable.md) — SIMD and vectorization choices
- [`f64::total_cmp`](https://doc.rust-lang.org/stable/std/primitive.f64.html#method.total_cmp)