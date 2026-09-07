# mem-zero-copy

> Use zero-copy patterns with slices and `Bytes`

## Why It Matters

Zero-copy means working with data without copying it. Instead of allocating new memory and copying bytes, you work with references to the original data. This dramatically reduces memory usage and improves performance, especially for large data. The `memchr` crate (2.8+) adds portable SIMD substring search on aarch64, x86_64, and wasm32.

Rust 1.98 also makes a common zero-copy parser task easier: once an iterator or parser gives you a substring/subslice borrowed from the original input, `str::substr_range` and `[T]::subslice_range` recover the corresponding range in the original input without searching or hand-written pointer arithmetic.

## Bad

```rust
// Copies every line into a new String
fn get_lines(data: &str) -> Vec<String> {
    data.lines()
        .map(|line| line.to_string())  // Allocates!
        .collect()
}

// Copies the entire buffer
fn process_packet(buffer: &[u8]) -> Vec<u8> {
    let header = buffer[0..16].to_vec();  // Copy!
    let body = buffer[16..].to_vec();      // Copy!
    // Process...
    [header, body].concat()  // Another copy!
}
```

## Good

```rust
// Zero-copy: returns references to original data
fn get_lines(data: &str) -> Vec<&str> {
    data.lines().collect()  // Just pointers!
}

// Zero-copy with slices
fn process_packet(buffer: &[u8]) -> (&[u8], &[u8]) {
    let header = &buffer[0..16];  // Just a pointer + length
    let body = &buffer[16..];     // Just a pointer + length
    (header, body)
}
```

## Rust 1.98+: Recover Original Ranges From Borrowed Views

When a substring or subslice was actually derived from a larger input, use the standard-library range APIs instead of searching for equal contents or subtracting raw pointers yourself:

```rust
use core::range::Range;

fn fields(input: &str) -> Vec<Range<usize>> {
    input
        .split(',')
        .map(|field| input.substr_range(field).expect("split result comes from input"))
        .collect()
}

fn main() {
    assert_eq!(
        fields("ab,cd,ef"),
        vec![
            Range { start: 0, end: 2 },
            Range { start: 3, end: 5 },
            Range { start: 6, end: 8 },
        ]
    );
}
```

The slice equivalent works the same way:

```rust
use core::range::Range;

fn main() {
    let data = &[0, 5, 10, 0, 20];
    let middle = &data[1..3];
    assert_eq!(data.subslice_range(middle), Some(Range { start: 1, end: 3 }));
}
```

Important semantics:

- these methods identify where a **borrowed view points inside the original allocation**; they do not search by contents;
- use `str::find`, `memchr`, `windows().position(...)`, or a parser/search algorithm when you have an independent equal value rather than a view derived from the source;
- `subslice_range` returns `None` if the view does not point within the source or is not element-aligned;
- `[T]::subslice_range` panics for zero-sized element types because pointer position cannot identify an element range meaningfully;
- the returned Rust 1.98 range is `core::range::Range<usize>`; convert to legacy `core::ops::Range` where an older API specifically requires that type.

This is especially useful for tokenizers and parsers that want to keep borrowed token text while also recording source spans.

## Using bytes::Bytes

```rust
use bytes::Bytes;

// Bytes provides zero-copy slicing with reference counting
let data = Bytes::from("hello world");

// Slicing doesn't copy - just increments refcount
let hello = data.slice(0..5);   // Zero-copy!
let world = data.slice(6..11); // Zero-copy!

// Both hello and world share the underlying allocation
// Memory is freed when all references are dropped
```

## memchr 2.8+ SIMD Substring Search

`memchr` 2.8+ provides portable SIMD-accelerated substring search:

```rust
use memchr::memmem;

// Pre-compiled finder for repeated searches (SIMD)
let finder = memmem::Finder::new("needle");
for haystack in haystacks {
    if let Some(pos) = finder.find(haystack.as_bytes()) {
        // Found at pos — no allocation, SIMD-accelerated
        process(&haystack[pos..]);
    }
}

// One-shot search
use memchr::memchr;
fn find_newline(data: &[u8]) -> Option<usize> {
    memchr(b'\n', data)  // SIMD on aarch64/x86_64/wasm32
}

// Find all occurrences
use memchr::memchr_iter;
fn count_newlines(data: &[u8]) -> usize {
    memchr_iter(b'\n', data).count()
}
```

## stringzilla (Alternative)

For workloads where `memchr` isn't fast enough, `stringzilla` provides even faster SIMD string operations:

```rust
// stringzilla offers SIMD-accelerated contains, find, count, etc.
// https://github.com/ashvardanian/stringzilla
```

## Zero-Copy Parsing

```rust
// Bad: Copies each parsed field
struct ParsedBad {
    name: String,
    value: String,
}

fn parse_bad(input: &str) -> ParsedBad {
    let (name, value) = input.split_once('=').unwrap();
    ParsedBad {
        name: name.to_string(),   // Copy!
        value: value.to_string(), // Copy!
    }
}

// Good: References into original string
struct Parsed<'a> {
    name: &'a str,
    value: &'a str,
}

fn parse_good(input: &str) -> Parsed<'_> {
    let (name, value) = input.split_once('=').unwrap();
    Parsed { name, value }  // Zero-copy!
}
```

## Combining with Cow

```rust
use std::borrow::Cow;

// Zero-copy when possible, copy when needed
fn normalize<'a>(input: &'a str) -> Cow<'a, str> {
    if input.contains('\t') {
        // Must copy to modify
        Cow::Owned(input.replace('\t', "    "))
    } else {
        // Zero-copy reference
        Cow::Borrowed(input)
    }
}
```

## When Zero-Copy Isn't Possible

```rust
// Need to modify data - must copy
fn uppercase(s: &str) -> String {
    s.to_uppercase()  // Creates new String
}

// Need data to outlive source
fn store_for_later(s: &str) -> String {
    s.to_string()  // Must copy for ownership
}

// Cross-thread transfer (without Arc)
fn send_to_thread(data: &[u8]) {
    let owned = data.to_vec();  // Must copy
    std::thread::spawn(move || {
        process(&owned);
    });
}
```

## See Also

- [own-cow-conditional](own-cow-conditional.md) - Use Cow for conditional ownership
- [own-borrow-over-clone](own-borrow-over-clone.md) - Prefer borrowing over cloning
- [own-range-copy](own-range-copy.md) - Rust 1.96+ copyable range values and legacy interop
- [mem-arena-allocator](mem-arena-allocator.md) - Arena allocators for batch operations