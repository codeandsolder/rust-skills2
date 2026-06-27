# mem-compact-string

> Use compact string types for memory-constrained string storage

## Why It Matters

Standard `String` is 24 bytes (pointer + length + capacity). For applications storing millions of short strings, this overhead dominates. Compact string libraries store small strings inline (no heap allocation) and use optimized layouts for larger strings. **`EcoString` from ecow 0.3.0** (May 2026, by the Typst team) is now the smallest option at 16 bytes with O(1) clone.

## Bad

```rust
struct User {
    id: u64,
    // Most usernames are < 24 chars, but String is always 24 bytes + heap
    username: String,
    email: String,
}

// 1 million users = 24 bytes * 2 * 1M = 48MB just for String metadata
// Plus all the heap allocations for actual content
```

## Good

```rust
use ecow::EcoString;

struct User {
    id: u64,
    // EcoString: 16 bytes, strings ≤ 15 chars are inline (no heap)
    username: EcoString,
    email: EcoString,
}

// Most usernames fit inline = zero heap allocations
// 16 bytes vs 24 bytes per field = 16MB saved per million users
```

## Compact String Libraries

### compact_str 0.9.0 (branchless, zeroize support)

```rust
use compact_str::{CompactString, ToCompactString, format_compact};

// Inline storage for strings ≤ 24 bytes (branchless access in 0.9+)
let small: CompactString = "hello".into();  // No heap allocation

// Automatic heap fallback for larger strings
let large: CompactString = "x".repeat(100).into();

// String-like API
let mut s = CompactString::new("hello");
s.push_str(" world");
assert_eq!(s.as_str(), "hello world");

// Format macro
let s = format_compact!("value: {}", 42);

// ToCompactString trait (0.9+) for any Display type
let s: CompactString = 42.to_compact_string();
```

### smartstring 1.0.1

```rust
use smartstring::{SmartString, LazyCompact};

// Default is LazyCompact: 24 bytes inline capacity
let s: SmartString<LazyCompact> = "short string".into();

// Compact mode: 23 bytes inline on 64-bit
use smartstring::Compact;
let s: SmartString<Compact> = "hello".into();
```

### ecow 0.3.0 (copy-on-write, smallest footprint)

```rust
use ecow::EcoString;

// Clone is O(1) — shares underlying data, just bumps refcount
let s1: EcoString = "shared data".into();
let s2 = s1.clone();  // Cheap, shares allocation

// Copy-on-write: only allocates on mutation
let mut s3 = s1.clone();
s3.push_str(" modified");  // Now allocates, others still share

// 16 bytes total — smallest compact string type
assert_eq!(std::mem::size_of::<EcoString>(), 16);
```

## Memory Comparison

```rust
use std::mem::size_of;

// All different sizes, different inline capacities
assert_eq!(size_of::<String>(), 24);
assert_eq!(size_of::<compact_str::CompactString>(), 24);
assert_eq!(size_of::<smartstring::SmartString>(), 24);
assert_eq!(size_of::<ecow::EcoString>(), 16);  // Smallest!
```

## Trade-off Table (2026)

| Type | Size | Inline Cap. | Clone | Best For |
|------|------|------------|-------|----------|
| `String` | 24 | 0 (heap) | O(n), allocates | General purpose, mutation-heavy |
| `CompactString` | 24 | 24 bytes | O(n), allocates | Many small strings, compact_str 0.9 |
| `SmartString<LazyCompact>` | 24 | 23 bytes | O(n), allocates | Drop-in String replacement |
| `EcoString` | 16 | 15 bytes | O(1), refcount | Clone-heavy, caches, templates |
| `Box<str>` | 16 | 0 (heap) | O(n) | Immutable, read-only strings |

## When to Use

```rust
// ✅ Good: Many short strings in memory
struct Dictionary {
    words: Vec<EcoString>,  // Millions of short words, 16 bytes each
}

// ✅ Good: Frequently cloned strings
struct Template {
    parts: Vec<EcoString>,  // O(1) clone for shared templates
}

// ✅ Good: Cache values
struct Cache {
    // EcoString clones without touching the allocator
    entries: HashMap<Key, EcoString>,
}

// ❌ Don't: Hot path string manipulation
fn transform(s: &str) -> String {
    // Standard String is optimized for manipulation
    s.to_uppercase()
}

// ❌ Don't: API boundaries (prefer &str or String for interop)
pub fn public_api(input: EcoString) { }  // Forces dependency
pub fn public_api(input: impl Into<String>) { }  // Better
```

## Cargo.toml

```toml
[dependencies]
compact_str = "0.9"
# or
smartstring = "1.0.1"
# or
ecow = "0.3"
```

## See Also

- [mem-ecow-clone-heavy](./mem-ecow-clone-heavy.md) — EcoString deep-dive for clone-heavy workloads
- [mem-boxed-slice](./mem-boxed-slice.md) - Box<str> for immutable strings
- [mem-arc-str](./mem-arc-str.md) — `Arc<str>` for thread-shared strings
- [own-cow-conditional](./own-cow-conditional.md) - Cow<str> for borrow-or-own
- [mem-smallvec](./mem-smallvec.md) - Similar concept for Vec
