# mem-boxed-slice

> Use `Box<[T]>` instead of `Vec<T>` for fixed-size heap data

## Why It Matters

`Vec<T>` stores three words: pointer, length, and capacity. When you know a collection won't grow, `Box<[T]>` stores only pointer and length (2 words), saving 8 bytes per instance. More importantly, it communicates intent: "this data is fixed-size." For large numbers of fixed collections, this adds up.

**Rust 1.87+** guarantees that `Vec::with_capacity(N).capacity() == N` exactly, making `into_boxed_slice()` more predictable — you know the exact allocation size before shrinking.

## Bad

```rust
struct Document {
    // Vec signals "might grow" but we never push after creation
    paragraphs: Vec<Paragraph>,  // 24 bytes: ptr + len + capacity
}

fn load_document(data: &[u8]) -> Document {
    let paragraphs: Vec<Paragraph> = parse_paragraphs(data);
    // paragraphs has capacity >= len, wasting the capacity field
    Document { paragraphs }
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
struct Document {
    // Box<[T]> signals "fixed size" - clear intent
    paragraphs: Box<[Paragraph]>,  // 16 bytes: ptr + len (as fat pointer)
}

fn load_document(data: &[u8]) -> Document {
    let paragraphs: Vec<Paragraph> = parse_paragraphs(data);
    Document { 
        paragraphs: paragraphs.into_boxed_slice()  // Shrinks + converts
    }
}
```

## Memory Layout

```rust
use std::mem::size_of;

// Vec: 24 bytes on 64-bit
assert_eq!(size_of::<Vec<u8>>(), 24);  // ptr(8) + len(8) + cap(8)

// Box<[T]>: 16 bytes (fat pointer)
assert_eq!(size_of::<Box<[u8]>>(), 16);  // ptr(8) + len(8)

// Savings per instance: 8 bytes
// For 1 million instances: 8 MB saved
```

## Conversion Patterns

```rust
// Vec to Box<[T]>
let vec: Vec<i32> = vec![1, 2, 3, 4, 5];
let boxed: Box<[i32]> = vec.into_boxed_slice();

// Box<[T]> back to Vec (if you need to grow)
let vec_again: Vec<i32> = boxed.into_vec();

// From iterator
let boxed: Box<[i32]> = (0..100).collect::<Vec<_>>().into_boxed_slice();

// Shrink Vec first if it has excess capacity
let mut vec = Vec::with_capacity(1000);
vec.extend(0..10);
vec.shrink_to_fit();  // Reduce capacity to length
let boxed = vec.into_boxed_slice();  // Now no wasted allocation
```

## Anti-Pattern: Vec Round-Trip

Avoid converting `Box<[T]>` back to `Vec<T>` just for temporary mutation:

```rust
// ❌ Bad: converts back and forth, wastes allocation
fn update(boxed: &mut Box<[i32]>, add: i32) {
    let mut vec = boxed.clone().into_vec();  // allocates + copies
    vec.push(add);
    *boxed = vec.into_boxed_slice();         // allocates again
}

// ✅ Better: collect into a new Box<[T]> directly
fn update(boxed: &[i32], add: i32) -> Box<[i32]> {
    let mut vec = boxed.to_vec();  // must copy, but one allocation
    vec.push(add);
    vec.into_boxed_slice()
}

// ✅ Best: use Vec when you need mutation
struct Document {
    paragraphs: Vec<Paragraph>,  // Use Vec directly if you'll modify
}
```

## When to Use What

| Type | Use When |
|------|----------|
| `Vec<T>` | Collection may grow/shrink |
| `Box<[T]>` | Fixed-size, heap-allocated, many instances |
| `[T; N]` | Fixed-size, stack-allocated, size known at compile time |
| `&[T]` | Borrowed view, don't need ownership |

## Box<str> for Immutable Strings

Same principle applies to strings:

```rust
use std::mem::size_of;

// String: 24 bytes (like Vec<u8>)
assert_eq!(size_of::<String>(), 24);

// Box<str>: 16 bytes
assert_eq!(size_of::<Box<str>>(), 16);

// For immutable strings
struct Name {
    value: Box<str>,  // Saves 8 bytes vs String
}

impl Name {
    fn new(s: &str) -> Self {
        Name { value: s.into() }  // &str -> Box<str>
    }
}

// Or from String
let s = String::from("hello");
let boxed: Box<str> = s.into_boxed_str();
```

## Real-World Example

```rust
// Cache with millions of entries
struct Cache {
    // 8 bytes saved per entry adds up
    entries: HashMap<Key, Box<[u8]>>,
}

impl Cache {
    fn insert(&mut self, key: Key, data: Vec<u8>) {
        // Convert to boxed slice for storage
        self.entries.insert(key, data.into_boxed_slice());
    }
    
    fn get(&self, key: &Key) -> Option<&[u8]> {
        // Returns regular slice reference
        self.entries.get(key).map(|b| b.as_ref())
    }
}
```

## See Also

- [mem-with-capacity](./mem-with-capacity.md) - Pre-allocating when size is known
- [mem-arc-str](./mem-arc-str.md) — `Arc<str>` over `Arc<String>` (same rationale, thread-safe)
- [own-slice-over-vec](./own-slice-over-vec.md) - Using slices in function parameters
- [mem-compact-string](./mem-compact-string.md) - Compact string alternatives
