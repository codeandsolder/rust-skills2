# num-cast-try-from

> Avoid `as` for narrowing casts; use `From` for widening and `TryFrom` for narrowing

## Why It Matters

Integer `as` casts intentionally truncate or reinterpret bits on narrowing (`300u32 as u8 == 44`) and produces surprising results on float-to-integer conversion (values outside range saturate to the type's min/max since Rust 1.45, but `NaN` becomes `0`). These behaviors are easy to miss. For primitive integer conversions, use the standard lossless `From` implementations where available and range-checked `TryFrom` otherwise. User-defined trait implementations are semantic contracts, not compiler proofs of losslessness.

## Bad

```rust
fn narrow(x: u32) -> u8 {
    x as u8  // silently truncates: 300 becomes 44
}

fn to_index(f: f64) -> usize {
    f as usize  // NaN becomes 0, negatives become 0, may truncate
}

fn widen(x: u8) -> u32 {
    x as u32  // works, but hides that this is always safe
}
```

## Good

<!-- rust-check: run -->
```rust
use std::convert::TryFrom;

// widening: From<u8> for u32 is always lossless — won't compile if lossy
fn widen(x: u8) -> u32 {
    u32::from(x)
    // or: x.into()
}

// narrowing: TryFrom makes the failure case explicit
fn narrow(x: u32) -> Result<u8, <u8 as TryFrom<u32>>::Error> {
    u8::try_from(x)
    // or: x.try_into()
}

// Float -> index: truncate nonnegative values, then check the integer bound.
fn float_to_index(f: f64, len: usize) -> Option<usize> {
    // The exclusive integer range endpoint is 2^usize::BITS, exactly
    // representable as f64 on supported Rust pointer widths.
    let upper = (usize::MAX as f64) + 1.0;
    if !f.is_finite() || f < 0.0 || f >= upper {
        return None;
    }
    let index = f as usize;
    (index < len).then_some(index)
}

fn main() {
    assert_eq!(widen(255), 255);
    assert!(narrow(300).is_err());
    assert_eq!(narrow(200), Ok(200));
    assert_eq!(float_to_index(f64::NAN, 10), None);
    assert_eq!(float_to_index(f64::INFINITY, 10), None);
    assert_eq!(float_to_index(f64::NEG_INFINITY, 10), None);
    assert_eq!(float_to_index(-0.5, 10), None);
    assert_eq!(float_to_index(-0.0, 10), Some(0));
    assert_eq!(float_to_index(3.9, 10), Some(3));
    assert_eq!(float_to_index(10.0, 10), None);
    assert_eq!(float_to_index(0.0, 0), None);
    assert_eq!(float_to_index(usize::MAX as f64 + 1.0, usize::MAX), None);
    #[cfg(target_pointer_width = "64")]
    assert_eq!(float_to_index(9_007_199_254_740_992.0, 9_007_199_254_740_993),
        Some(9_007_199_254_740_992));
}
```

On 64-bit targets, comparing a float to `len as f64` is insufficient: large lengths can round before comparison. Check the conversion range first, then compare in integer space. If fractional input is invalid rather than intentionally truncated, reject it explicitly.

## Key Points

- The standard library does not implement `From<u32> for u8`; custom `From` implementations must honor their documented infallible conversion semantics.
- Standard fallible integer conversions use `TryFromIntError`; other conversions have their own associated error type.
- Reserve `as` for:
  - Pointer casts (e.g., `*const u8 as *mut u8`) that are intentional.
  - Float-to-integer when you have verified the range and documented the intent.
  - `usize` ↔ pointer-sized integer only when you explicitly need to expose or
    inject provenance. Prefer strict provenance pointer APIs (stable since Rust 1.84):
    `ptr.addr()` instead of `ptr as usize`, and `ptr.map_addr(|a| ...)` instead of
    casting through an integer to manipulate a pointer's address.
- When using `.try_into()`, the turbofish or type annotation is often needed to help inference: `let n: u8 = x.try_into()?;`

## See Also

- [conv-tryfrom-fallible](conv-tryfrom-fallible.md) - implement `TryFrom` for your own fallible conversions
- [num-overflow-explicit](num-overflow-explicit.md) - handle integer overflow explicitly with `checked_`/`saturating_`/`wrapping_`
