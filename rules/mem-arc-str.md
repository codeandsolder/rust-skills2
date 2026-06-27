# mem-arc-str

> Prefer `Arc<str>` over `Arc<String>` for thread-shared immutable strings

**Rule**: `mem-arc-str`

## Why It Matters

`Arc<String>` stores a pointer to a 24-byte `String` (ptr + len + cap), which itself points to the heap-allocated buffer. That's 8 bytes of capacity metadata that is never used once the string is finalized. `Arc<str>` uses a fat pointer (ptr + len on the stack) with no capacity field, saving 8 bytes per shared instance. The same rationale applies as `Box<[T]>` vs `Vec<T>` (see [mem-boxed-slice](mem-boxed-slice.md)).

## Bad

```rust
use std::sync::Arc;

// Arc<String> stores unnecessary capacity field
struct SharedConfig {
    name: Arc<String>,     // 8 bytes: ptr to String(24) → heap
    version: Arc<String>,
}

// Each Arc<String> allocation includes a 24-byte String header
// The capacity field is always 0 (from &str) or wasted
```

## Good

```rust
use std::sync::Arc;

// Arc<str> stores just ptr + len (fat pointer, 16 bytes)
struct SharedConfig {
    name: Arc<str>,     // 16 bytes: ptr + len directly to UTF-8 bytes
    version: Arc<str>,
}
```

## Memory Layout

```rust
use std::mem::size_of;

// Arc<String> — two indirections
assert_eq!(size_of::<Arc<String>>(), 8);   // Pointer to String(24) → heap
// Total per-unique allocation: 8 (Arc) + 24 (String) + N (data) = 32 + N

// Arc<str> — one indirection (fat pointer on stack)
assert_eq!(size_of::<Arc<str>>(), 16);     // Fat pointer → heap
// Total per-unique allocation: 16 (Arc fat ptr) + N (data) = 16 + N
// Savings: 8 bytes per instance, 24 bytes per unique allocation
```

## Conversion

```rust
// From &str
let shared: Arc<str> = Arc::from("hello world");

// From String
let s = String::from("hello");
let shared: Arc<str> = Arc::from(s);   // Consumes String, reuses allocation
// Or: let shared: Arc<str> = s.into();

// From Arc<String> (if unavoidable)
let arc_string = Arc::new(String::from("hello"));
let arc_str: Arc<str> = Arc::from(&*arc_string as &str);  // Reborrows
// Note: this still requires cloning the Arc, not the data
```

## When to Use

```rust
use std::sync::Arc;

// ✅ Good: Immutable shared strings
struct Labels {
    en: Arc<str>,
    de: Arc<str>,
    fr: Arc<str>,
}

// ✅ Good: Large cache values
struct CacheEntry {
    key: Arc<str>,
    value: Arc<str>,
}

// ✅ Good: Interned strings (with Arc dedup)
fn intern(s: &str, pool: &mut HashSet<Arc<str>>) -> Arc<str> {
    if let Some(existing) = pool.get(s) {
        existing.clone()  // Arc refcount bump only
    } else {
        let interned: Arc<str> = Arc::from(s);
        pool.insert(interned.clone());
        interned
    }
}

// ❌ Avoid: Need to mutate the string
struct Mutable {
    buffer: Arc<str>,  // Arc<str> is immutable; wrap in Mutex
    // Prefer Arc<String> or Arc<Mutex<String>> for mutation
}
```

## Comparison: Arc<str> vs Alternatives

| Type | Stack Size | Capacity Field | Mutation | Clone Cost |
|------|-----------|---------------|----------|------------|
| `Arc<String>` | 8 bytes | Yes (24B on heap) | Via `Arc::make_mut` | Refcount |
| `Arc<str>` | 16 bytes | No | Immutable | Refcount |
| `EcoString` | 16 bytes | Inline (15B) | Copy-on-write | Refcount |
| `Arc<Box<str>>` | 8 bytes | No | Immutable | Refcount |

## Cargo.toml

```toml
[dependencies]
# No extra dependencies — Arc and str are in std
```

## See Also

- [mem-boxed-slice](mem-boxed-slice.md) — Same rationale for `Box<[T]>` vs `Vec<T>`
- [mem-compact-string](mem-compact-string.md) — Compact string alternatives
- [mem-ecow-clone-heavy](mem-ecow-clone-heavy.md) — `EcoString` for non-thread-shared clone-heavy
