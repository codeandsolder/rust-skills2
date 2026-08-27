# mem-arrayvec

> Use `ArrayVec<T, N>` when a hard capacity belongs in the type

## Why It Matters

`ArrayVec<T, N>` from `arrayvec` stores its elements inline in a fixed-size array and never grows onto the heap. Its capacity is the const generic `N`; `push` panics when full, while fallible methods such as `try_push` return a capacity error.

That makes `ArrayVec` useful when a hard upper bound is part of the design—for example bounded protocol fields, embedded/no-alloc code, or small temporary buffers. It is not automatically better than `Vec`: the inline storage is part of every `ArrayVec` value, so a large capacity makes the value itself large regardless of its current length.

## Bad

```rust
// If the protocol guarantees at most eight codes, an unbounded Vec does not
// express that invariant in the result type.
fn collect_codes(input: &str) -> Vec<u16> {
    input.split(',')
        .filter_map(|part| part.parse().ok())
        .collect()
}
```

## Good

<!-- rust-check: compile -->
```rust
use arrayvec::ArrayVec;

fn parse_codes(input: &str) -> ArrayVec<u16, 8> {
    let mut codes = ArrayVec::new();
    for part in input.split(',') {
        let Ok(code) = part.parse::<u16>() else {
            continue;
        };
        if codes.try_push(code).is_err() {
            break;
        }
    }
    codes
}

assert_eq!(&parse_codes("10,20,30")[..], &[10, 20, 30]);
```

For a crate that needs `no_std`, disable `arrayvec`'s default `std` feature at the dependency level. `#![no_std]` is a crate-level choice, not an annotation for an individual function.

## `ArrayVec` vs `SmallVec` vs `Vec`

| Type | Storage behavior | Use when |
|------|------------------|----------|
| `Vec<T>` | Heap-backed, grows dynamically | Size is not tightly bounded |
| `SmallVec<[T; N]>` | Inline up to N, may spill to heap | Usually small but growth is allowed |
| `ArrayVec<T, N>` | Always inline, hard capacity N | Exceeding N must be handled or treated as a bug |

## Capacity APIs

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

`FromIterator` cannot return a capacity error, so collecting more than `N` items into an `ArrayVec<T, N>` panics. When the input length is not guaranteed, prefer `try_push` or another explicitly fallible construction path.

## `ArrayString` for Bounded Strings

```rust
use arrayvec::ArrayString;
use std::fmt::Write as _;

fn format_code(code: u32) -> ArrayString<16> {
    let mut s = ArrayString::new();
    write!(&mut s, "CODE-{code:04}").unwrap();
    s
}

assert_eq!(format_code(42).as_str(), "CODE-0042");
```

## When Not to Use It

Avoid choosing a large arbitrary capacity merely to avoid allocation. An `ArrayVec<u8, 1_000_000>` carries roughly a megabyte of inline element storage in every value. If the size is genuinely variable, use `Vec`; if a small inline fast path with heap fallback is desirable, consider `SmallVec`.

## Cargo.toml

```toml
[dependencies]
arrayvec = "0.7"
```

As of August 2026, the current 0.7 release is 0.7.8. Prefer a compatible-series requirement unless the project has a reason to pin a patch release.

## See Also

- [mem-smallvec](./mem-smallvec.md) - When heap fallback is acceptable
- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocating Vec capacity
- [own-move-large](./own-move-large.md) - Large inline types and move cost
