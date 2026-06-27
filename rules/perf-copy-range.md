# perf-copy-range

> Use `core::range::Range` for Copy-compatible range storage

**Rule**: `perf-copy-range`

## Why It Matters

`core::ops::Range` implements `Iterator`, which makes it non-Copy — an Iterator can't be Copy because it has mutable iteration state. `core::range::Range` (stabilized in Rust 1.96) implements `IntoIterator` instead, enabling `Copy`. This allows storing range bounds in Copy types and passing them by value without ownership semantics.

## Bad

```rust
use std::ops::Range;

// core::ops::Range is not Copy
#[derive(Clone)]  // Can't derive Copy!
struct ChunkMeta {
    offset: Range<usize>,
    length: usize,
}

// Passing ops::Range requires ownership or &mut
fn process_chunks(chunks: Vec<Range<usize>>) {
    for range in chunks {
        // Range is consumed by the for loop (IntoIterator)
        process(range);
        // Can't use `range` again
    }
}
```

## Good

```rust
use core::range::Range;

// core::range::Range is Copy
#[derive(Clone, Copy)]
struct ChunkMeta {
    offset: Range<usize>,  // Now Copy!
    length: usize,
}

// Passing by value without ownership issues
fn process_chunks(chunks: &[Range<usize>]) {
    for &range in chunks {
        // Copy, so we can iterate
        for i in range {
            process_index(i);
        }
        // range is still available
    }
}

// Store in arrays without cloning
const RANGES: [Range<usize>; 3] = [
    Range { start: 0, end: 10 },
    Range { start: 10, end: 20 },
    Range { start: 20, end: 30 },
];
```

## Conversion

`core::range::Range` and `core::ops::Range` are interconvertible:

```rust
use core::ops::Range as OpsRange;
use core::range::Range;

// Convert ops::Range to range::Range (always succeeds)
let ops: OpsRange<usize> = 0..10;
let range: Range<usize> = ops.into();

// Convert range::Range to ops::Range (always succeeds)
let range: Range<usize> = Range { start: 0, end: 10 };
let ops: OpsRange<usize> = range.into();
```

## Use Cases

### Storing range metadata in Copy-heavy structs

```rust
use core::range::Range;

#[derive(Clone, Copy)]
struct Span {
    range: Range<usize>,
    source_id: u32,
}

fn merge_spans(a: Span, b: Span) -> Span {
    Span {
        range: Range {
            start: a.range.start.min(b.range.start),
            end: a.range.end.max(b.range.end),
        },
        source_id: a.source_id,
    }
}
```

### Passing ranges without lifetime or ownership friction

```rust
use core::range::Range;

// Previously needed &Range<usize> or Clone
fn contains(range: Range<usize>, point: usize) -> bool {
    range.start <= point && point < range.end
}

// Can now be Copy — no borrow issues
fn intersect(a: Range<usize>, b: Range<usize>) -> Option<Range<usize>> {
    let start = a.start.max(b.start);
    let end = a.end.min(b.end);
    if start < end {
        Some(Range { start, end })
    } else {
        None
    }
}
```

## API Compatibility

| API | Since | Implements Iterator | Implements Copy |
|-----|-------|-------------------|-----------------|
| `core::ops::Range` | 1.0 | Yes | No |
| `core::range::Range` | 1.96 | No (IntoIterator) | Yes |

## Performance

Using `core::range::Range` in Copy types avoids:
- Reference indirection when passing ranges by value
- Clone calls when reusing a range
- Lifetime annotations in function signatures

## See Also

- [perf-iter-over-index](./perf-iter-over-index.md) - Prefer iterators over indexing
- [own-copy-small](./own-copy-small.md) - Derive Copy for small, trivial types
- [type-newtype-ids](./type-newtype-ids.md) - Newtype patterns
