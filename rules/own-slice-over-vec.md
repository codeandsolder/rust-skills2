# own-slice-over-vec

> Accept borrowed views such as `&[T]`, `&str`, and `&Path` when the implementation only needs a view

## Why It Matters

A parameter typed as `&Vec<T>` unnecessarily requires the caller to own a `Vec<T>`. A parameter typed as `&[T]` accepts a vector, array, boxed slice, subslice, and other sources that can provide a slice. The same principle applies to `&String` versus `&str`, and usually to `&PathBuf` versus `&Path`.

Use the narrowest borrowed interface that expresses what the function actually needs. Accept an owned type when the function needs ownership, capacity-specific operations, or another property that the borrowed view does not provide.

## Good: Borrow the View You Need

```rust
fn sum(numbers: &[i32]) -> i32 {
    numbers.iter().sum()
}

fn greet(name: &str) -> String {
    format!("Hello, {name}")
}

fn main() {
    let values = vec![1, 2, 3];
    let array = [4, 5, 6];

    assert_eq!(sum(&values), 6);
    assert_eq!(sum(&array), 15);
    assert_eq!(sum(&values[1..]), 5);

    let owned = String::from("Alice");
    assert_eq!(greet(&owned), "Hello, Alice");
    assert_eq!(greet("Bob"), "Hello, Bob");
}
```

`&Vec<T>` can coerce to `&[T]` because `Vec<T>` dereferences to `[T]`; `&String` similarly coerces to `&str`. The coercion applies to the **reference**, not by converting an owned `Vec<T>` value directly into a reference.

## Other Slice Owners Work Too

```rust
use std::sync::Arc;

fn checksum(bytes: &[u8]) -> u32 {
    bytes.iter().map(|&byte| u32::from(byte)).sum()
}

fn main() {
    let boxed: Box<[u8]> = vec![1, 2, 3].into_boxed_slice();
    let shared: Arc<[u8]> = Arc::from([4, 5, 6]);

    assert_eq!(checksum(&boxed), 6);
    assert_eq!(checksum(&shared), 15);
}
```

This flexibility is one of the main reasons borrowed collection APIs conventionally take slices rather than references to a particular owning collection.

## `&Path` Instead of `&PathBuf`

For a borrowed path, `&Path` is usually the direct analogue of `&str` and `&[T]`.

```rust
use std::path::{Path, PathBuf};

fn extension(path: &Path) -> Option<&str> {
    path.extension()?.to_str()
}

fn main() {
    let owned = PathBuf::from("settings.toml");
    assert_eq!(extension(&owned), Some("toml"));
    assert_eq!(extension(Path::new("notes.txt")), Some("txt"));
}
```

`impl AsRef<Path>` can be useful for a public convenience API that intentionally accepts several path-like input types, but it is not automatically “better” than `&Path`. A generic parameter changes the API and can cause monomorphization; use it when that caller flexibility is worth it.

## Accept Ownership When You Need Ownership

```rust
#[derive(Debug)]
struct Logger {
    prefix: String,
}

impl Logger {
    fn new(prefix: String) -> Self {
        Self { prefix }
    }

    fn prefix(&self) -> &str {
        &self.prefix
    }
}

fn main() {
    let prefix = String::from("network");
    let logger = Logger::new(prefix);
    assert_eq!(logger.prefix(), "network");
}
```

Taking `String` is appropriate here because the logger stores the value after the call returns. The caller can move an existing string or choose explicitly to clone one.

## `core::range::Range` (Rust 1.96+)

Rust 1.96 stabilized the new `core::range::Range<Idx>`. Unlike the legacy `core::ops::Range<Idx>`, the new range is `Copy` when `Idx: Copy`, which can be useful for APIs that want a reusable range value.

```rust
use core::range::Range;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Span(Range<usize>);

fn take(data: &[u8], range: Range<usize>) -> &[u8] {
    &data[range]
}

fn main() {
    let span = Span(Range::from(1..4));
    let again = span;

    assert_eq!(take(b"hello", span.0), b"ell");
    assert_eq!(again.0, Range { start: 1, end: 4 });
}
```

The distinction is important today: `start..end` syntax still constructs the **legacy** range type. Convert explicitly with `core::range::Range::from(start..end)` when you need the new type. The standard-library documentation says a future edition is planned to make range syntax construct the new types, but that has not happened yet.

Do not mechanically replace every `core::ops::Range` in an existing API. Ecosystem traits and signatures may still use the legacy type, and conversion/interoperability can matter more than `Copy` semantics.

See [own-range-copy](./own-range-copy.md) for the dedicated range guidance.

## Fixed-Size Slice Views

When an API needs exactly `N` elements, a fixed-size array reference can communicate that invariant more strongly than a plain slice. Current stable Rust provides helpers such as `slice::as_array` and `array_windows`; use them when the fixed size is meaningful to the algorithm rather than merely to chase a bounds-check micro-optimization.

```rust
fn header(bytes: &[u8]) -> Option<&[u8; 4]> {
    bytes.get(..4)?.as_array()
}

fn main() {
    assert_eq!(header(b"RUSTlang"), Some(b"RUST"));
}
```

## Decision Guide

| Need | Typical parameter |
|---|---|
| Read/write a sequence without owning it | `&[T]` / `&mut [T]` |
| Read text without owning it | `&str` |
| Read a filesystem path | `&Path` |
| Store or consume a vector/string/path | owned `Vec<T>` / `String` / `PathBuf` |
| Need vector-specific capacity/push behavior | `&Vec<T>` / `&mut Vec<T>` only when those semantics are genuinely required |
| Convenience over several path-like input types | sometimes `impl AsRef<Path>` |

## See Also

- [api-impl-asref](./api-impl-asref.md) — `AsRef` API tradeoffs
- [own-borrow-over-clone](./own-borrow-over-clone.md) — borrowing versus cloning
- [own-range-copy](./own-range-copy.md) — new Copy range types
