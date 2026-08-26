# mem-arrayvec

> Use `ArrayVec<T, N>` for fixed-capacity collections that never heap-allocate

## Why It Matters

`ArrayVec` from the `arrayvec` 0.7 series stores up to `N` values inline and never grows onto the heap. Unlike `SmallVec`, which may spill to a heap allocation when its inline capacity is exceeded, `ArrayVec` has a hard compile-time capacity.

That makes it useful when a hard upper bound is part of the design—for example embedded/no-alloc code, bounded protocol fields, or small temporary buffers. It is not automatically better than `Vec`: large capacities increase the size of the containing value and can put substantial objects on the stack.

## Bad

```rust
// If the protocol guarantees at most eight items, an unbounded Vec does not
// express that invariant in the type.
fn collect_codes(input: &str) -> Vec<u16> {
    input.split(',')
        .filter_map(|part| part.parse().ok())
        .collect()
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: domain parser and sensor context -->
```rust
use arrayvec::ArrayVec;

struct ParsedOption;

fn parse_options(input: &str) -> ArrayVec<ParsedOption, 8> {
    let mut options = ArrayVec::new();
    for part in input.split(',') {
        let option = parse_option(part);
        if options.try_push(option).is_err() {
            break;
        }
    }
    options
}

// In a no_std crate, ArrayVec can be used with arrayvec's default `std`
// feature disabled.
fn collect_readings() -> ArrayVec<SensorReading, 16> {
    let mut readings = ArrayVec::new();
    for sensor in SENSORS.iter().take(readings.capacity()) {
        readings.push(sensor.read());
    }
    readings
}
```

Do not put `#[no_std]` on an individual function. `#![no_std]` is a crate-level attribute; configure the dependency/features for the crate that needs no-std operation.

## `ArrayVec` vs `SmallVec` vs `Vec`

| Type | Storage behavior | Use when |
|------|------------------|----------|
| `Vec<T>` | Heap-backed, grows dynamically | Size is not tightly bounded |
| `SmallVec<[T; N]>` | Inline up to N, may spill to heap | Usually small but growth is allowed |
| `ArrayVec<T, N>` | Always inline, hard capacity N | Exceeding N is an error/panic by policy |

## API Patterns

```rust
use arrayvec::ArrayVec;

let mut arr: ArrayVec<i32, 4> = ArrayVec::new();
arr.push(1);                    // panics if already full
arr.try_push(2).unwrap();       // returns CapacityError on overflow

assert_eq!(arr.capacity(), 4);
assert_eq!(arr.remaining_capacity(), 2);
assert!(!arr.is_full());

let collected: ArrayVec<i32, 4> = (0..4).collect();
assert_eq!(&collected[..], &[0, 1, 2, 3]);
```

`FromIterator` cannot return a capacity error, so collecting more than `N` items into an `ArrayVec<T, N>` panics. When the input length is not statically bounded, prefer `try_push` or another explicitly fallible construction path.

## `ArrayString` for Bounded Strings

```rust
use arrayvec::ArrayString;
use std::fmt::Write as _;

fn format_code(code: u32) -> ArrayString<16> {
    let mut s = ArrayString::new();
    write!(&mut s, "CODE-{code:04}").unwrap();
    s
}
```

## When Not to Use It

Avoid choosing an arbitrary large capacity merely to avoid allocation. An `ArrayVec<u8, 1_000_000>` makes every value roughly a megabyte even when empty. If the size is genuinely variable, use `Vec`; if a small inline fast path with heap fallback is desirable, consider `SmallVec`.

## Cargo.toml

```toml
[dependencies]
arrayvec = "0.7"
```

As of August 2026, the current 0.7 release line is 0.7.8. Prefer a compatible-series requirement unless the project has a reason to pin a patch release.

## See Also

- [mem-smallvec](./mem-smallvec.md) - When heap fallback is acceptable
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocating Vec capacity
- [own-move-large](./own-move-large.md) - Large inline types and move cost
