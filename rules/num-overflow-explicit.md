# num-overflow-explicit

> Handle integer overflow explicitly: `checked_`/`saturating_`/`wrapping_`/`overflowing_`

## Why It Matters

Overflow of ordinary integer addition, subtraction and multiplication is normally checked in dev profiles and wraps in release profiles without overflow checks. Cargo profiles can override those defaults. Division by zero and signed minimum divided by -1 have additional rules and can panic regardless of overflow-check settings. Choose an explicit operation when overflow is possible and its semantics matter; ordinary arithmetic is fine when the bounds are proved.

## Bad

```rust
fn add_score(current: u32, delta: u32) -> u32 {
    current + delta  // panics in debug, wraps silently in release
}

fn increment_counter(c: u8) -> u8 {
    c + 1  // wraps to 0 in release when c == 255
}
```

## Good

```rust
// checked_add: returns None on overflow — propagate or handle the error
fn add_score(current: u32, delta: u32) -> Option<u32> {
    current.checked_add(delta)
}

// saturating_add: clamps at the type's upper bound (u8::MAX == 255)
fn increment_saturating(c: u8) -> u8 {
    c.saturating_add(1)
}

// wrapping_add: intentional modular (two's complement) arithmetic
fn wrapping_sequence(n: u8) -> u8 {
    n.wrapping_add(1)
}

// overflowing_add: returns (result, did_overflow) — useful for carry detection
fn add_with_carry(a: u32, b: u32) -> (u32, bool) {
    a.overflowing_add(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_returns_none_on_overflow() {
        assert_eq!(add_score(u32::MAX, 1), None);
        assert_eq!(add_score(10, 5), Some(15));
    }

    #[test]
    fn saturating_clamps_at_max() {
        assert_eq!(increment_saturating(255), 255);
        assert_eq!(increment_saturating(10), 11);
    }

    #[test]
    fn wrapping_rolls_over() {
        assert_eq!(wrapping_sequence(255), 0);
    }

    #[test]
    fn overflowing_reports_carry() {
        assert_eq!(add_with_carry(u32::MAX, 1), (0, true));
        assert_eq!(add_with_carry(1, 2), (3, false));
    }
}
```

## Key Points

| Method family | Returns | Use when |
|---|---|---|
| `checked_*` | `Option<T>` | overflow is an error your caller must handle |
| `saturating_*` | `T` | clamping at the type's bounds is correct behavior |
| `wrapping_*` | `T` | modular arithmetic is intentional (e.g., checksums, ring buffers) |
| `overflowing_*` | `(T, bool)` | you need the result *and* know whether it overflowed |

These methods are available on all primitive integer types in the standard library (`u8` through `u128`, `i8` through `i128`, `usize`, `isize`). Not every arithmetic operation has every variant. Division/remainder and shifts have distinct domain and overflow semantics; check the precise method. For example, checked shifts reject an out-of-range shift count, not loss of high bits from a left shift. Wrapping division still rejects a zero divisor.

If validation proves arithmetic is in range, encode or preserve that proof and measure the hot loop. Do not weaken unrelated overflow checking or silently switch a checked algorithm to modular arithmetic to improve a benchmark.

## See Also

- [perf-benchmark-regression](./perf-benchmark-regression.md)

- [num-saturating-clamp](num-saturating-clamp.md) - bound values with `clamp` and saturating arithmetic
- [num-cast-try-from](num-cast-try-from.md) - avoid `as` for narrowing casts; prefer `TryFrom`
