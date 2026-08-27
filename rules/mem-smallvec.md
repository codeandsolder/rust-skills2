# mem-smallvec

> Use `SmallVec` when collections are usually small but may grow

## Why It Matters

`SmallVec<[T; N]>` stores up to `N` elements inline in the `SmallVec` value and spills to a heap allocation when it grows beyond that inline capacity. This can avoid allocations for the common small case while preserving a Vec-like growable API.

The trade-off is not free: inline storage makes every `SmallVec` value larger, moves can copy that inline storage, and operations must support both inline and spilled representations. Choose `N` from real workload data rather than folklore, and benchmark when this sits on a hot path.

As of August 2026, the stable 1.x release is SmallVec 1.15.2; a 2.0 alpha line also exists. Do not write production guidance against an alpha API unless the project intentionally depends on it.

## Bad

<!-- rust-check: compile -->
```rust
#[derive(Debug)]
struct ValidationError;
struct Input;

// A Vec is perfectly correct, but it allocates when the result is non-empty.
fn validate(_input: &Input) -> Vec<ValidationError> {
    let mut errors = Vec::new();
    errors.push(ValidationError);
    errors
}

fn get_path_components(path: &str) -> Vec<&str> {
    path.split('/').collect()
}
```

## Good

<!-- rust-check: compile -->
```rust
use smallvec::{smallvec, SmallVec};

#[derive(Debug)]
struct ValidationError;
struct Input;

fn get_path_components(path: &str) -> SmallVec<[&str; 8]> {
    path.split('/').collect()
}

fn validate(_input: &Input) -> SmallVec<[ValidationError; 4]> {
    let mut errors = SmallVec::new();
    errors.push(ValidationError);
    errors
}

let v: SmallVec<[i32; 4]> = smallvec![1, 2, 3];
assert!(!v.spilled());
```

The point is the workload distribution: if most values fit inline, the common case avoids a heap allocation. If many values spill, the larger inline representation may buy little.

## Choosing Inline Capacity

Prefer measurements or domain bounds:

```rust
use smallvec::SmallVec;

// A protocol allows at most four short routing tags in the common case, but
// forward-compatible inputs may contain more.
type RoutingTags<'a> = SmallVec<[&'a str; 4]>;

fn tags(input: &str) -> RoutingTags<'_> {
    input.split(',').filter(|s| !s.is_empty()).collect()
}
```

A type alias does not make `4` universally optimal; it documents the capacity chosen for this workload.

## Inspect Whether a Value Spilled

```rust
use smallvec::SmallVec;

let mut values: SmallVec<[u8; 4]> = SmallVec::new();
values.extend([1, 2, 3]);
assert!(!values.spilled());

values.extend([4, 5]);
assert!(values.spilled());
```

This is often more useful than relying on assumed struct sizes: actual representation size depends on element type, inline capacity, crate configuration, and target.

## When to Use Alternatives

| Situation | Prefer |
|-----------|--------|
| Usually small, occasionally larger | `SmallVec<[T; N]>` |
| Hard maximum, no heap fallback | `ArrayVec<T, N>` |
| Variable/unbounded and allocation is fine | `Vec<T>` |
| Known approximate final length | `Vec::with_capacity(...)` |

## Fixed-Capacity Alternative

```rust
use arrayvec::ArrayVec;

fn parse_rgb(s: &str) -> ArrayVec<u8, 3> {
    let mut components = ArrayVec::new();
    for part in s.split(',').take(3) {
        components.push(part.parse().unwrap());
    }
    components
}

assert_eq!(&parse_rgb("10,20,30")[..], &[10, 20, 30]);
```

## Cargo.toml

```toml
[dependencies]
smallvec = "1.15"
```

## See Also

- [mem-arrayvec](mem-arrayvec.md) - Use ArrayVec for fixed-max collections
- [mem-with-capacity](mem-with-capacity.md) - Pre-allocate when size is known
- [mem-thinvec](mem-thinvec.md) - Pointer-sized collection handles
