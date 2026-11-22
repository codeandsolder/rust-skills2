# mem-zero-copy

> Use zero-copy patterns with slices and `Bytes`

## Why It Matters

Zero-copy means working with data without copying it. Instead of allocating new memory and copying bytes, you work with references to the original data. This can reduce copying and allocations, especially for large data, but a small borrowed view can also retain a much larger backing allocation. Measure retention, locality and ownership costs. The `memchr` crate (2.8+) adds portable SIMD substring search on aarch64, x86_64, and wasm32.

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

<!-- rust-check: run -->
```rust
// Borrow the lines without allocating a collection when only iteration is needed.
fn get_lines(data: &str) -> impl Iterator<Item = &str> {
    data.lines()
}

// Zero-copy with slices; malformed input is a normal failure.
fn process_packet(buffer: &[u8]) -> Option<(&[u8], &[u8])> {
    buffer.split_at_checked(16)
}

fn main() {
    assert_eq!(get_lines("one\ntwo").collect::<Vec<_>>(), ["one", "two"]);
    assert_eq!(process_packet(&[0; 15]), None);
    let packet = [1_u8; 17];
    assert_eq!(process_packet(&packet), Some((&packet[..16], &packet[16..])));
}
```

## Rust 1.98+: Recover Original Ranges From Borrowed Views

When a substring or subslice was actually derived from a larger input, use the standard-library range APIs instead of searching for equal contents or subtracting raw pointers yourself:

<!-- rust-check: run -->
```rust
use core::range::Range;

fn fields(input: &str) -> Option<Vec<Range<usize>>> {
    input.split(',').map(|field| input.substr_range(field)).collect()
}

fn main() {
    assert_eq!(
        fields("ab,cd,ef"),
        Some(vec![
            Range { start: 0, end: 2 },
            Range { start: 3, end: 5 },
            Range { start: 6, end: 8 },
        ])
    );
    assert_eq!(fields(","), Some(vec![
        Range { start: 0, end: 0 },
        Range { start: 1, end: 1 },
    ]));
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

- these methods recover an address-derived range for a view already known to come from the input; they do not search by contents or establish pointer provenance;
- both methods can report a false positive for an independent empty view at the start or end address. Do not use their return value to prove allocation identity or an unsafe aliasing invariant;
- use `str::find`, `memchr`, `windows().position(...)`, or a parser/search algorithm when you have an independent equal value rather than a view derived from the source;
- `subslice_range` checks address containment and element alignment; note the documented empty-view exception above;
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

Stringzilla is another SIMD-oriented string-processing library. Compare representative operations and supported targets before choosing it:

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

fn parse_good(input: &str) -> Option<Parsed<'_>> {
    let (name, value) = input.split_once('=')?;
    Some(Parsed { name, value })
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

// An unscoped task that must outlive a borrowed input needs ownership.
fn send_to_thread(data: Vec<u8>) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || process(&data)) // Move existing allocation.
}
```

A scoped thread can borrow its input without copying, and a shared owner
can avoid a copy when independent lifetimes are necessary. Avoid retaining
a huge allocation for a tiny long-lived result; an intentional compact copy
may reduce memory usage.

## See Also

- [unsafe-strict-provenance](./unsafe-strict-provenance.md) — addresses are not allocation identity
- [own-cow-conditional](own-cow-conditional.md) - Use Cow for conditional ownership
- [own-borrow-over-clone](own-borrow-over-clone.md) - Prefer borrowing over cloning
- [own-range-copy](own-range-copy.md) - Rust 1.96+ copyable range values and legacy interop
- [mem-arena-allocator](mem-arena-allocator.md) - Arena allocators for batch operations