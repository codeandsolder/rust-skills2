# mem-ecow-clone-heavy

> Use `EcoString` for clone-heavy string workloads

**Rule**: `mem-ecow-clone-heavy`

## Why It Matters

Standard `String::clone()` is O(n) — it allocates new heap memory and copies every byte. For clone-heavy workloads (caches, templates, shared config), this dominates the allocator budget. `EcoString` from `ecow` 0.3.0 (May 2026, Typst team) is only 16 bytes (vs 24 for `String`), stores up to 15 bytes inline without heap allocation, and **clone() is O(1)** — just a refcount bump.

## Bad

```rust
use std::collections::HashMap;
use std::sync::Arc;

// Template system with many clones
struct Template {
    name: String,
    content: String,
}

struct TemplateCache {
    templates: HashMap<String, Template>,
}

fn render(cache: &TemplateCache, name: &str) -> String {
    let template = cache.templates.get(name).unwrap();
    // Each clone allocates! O(n) copies
    let name = template.name.clone();
    let content = template.content.clone();
    format!("Rendering: {} with {}", name, content)
}

// Clone-heavy config sharing
struct SharedConfig {
    host: String,
    token: String,
}

// Every clone of SharedConfig copies both strings
let config = Arc::new(SharedConfig {
    host: "api.example.com".into(),
    token: "s3cr3t".into(),
});

// Spawning 1000 workers: 1000 String clones = 1000 heap allocations
for _ in 0..1000 {
    let c = config.clone();
    spawn_worker(move || { let h = c.host.clone(); });
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
use ecow::EcoString;
use std::collections::HashMap;

struct Template {
    name: EcoString,      // 16 bytes, inline if ≤ 15 chars
    content: EcoString,   // Clone is O(1)
}

struct TemplateCache {
    templates: HashMap<EcoString, Template>,
}

fn render(cache: &TemplateCache, name: &str) -> String {
    let template = cache.templates.get(name).unwrap();
    // Both clones are O(1) — just bump refcounts
    let name = template.name.clone();
    let content = template.content.clone();
    format!("Rendering: {} with {}", name, content)
}

// Thread-safe config sharing
struct SharedConfig {
    host: EcoString,   // O(1) clone, no allocator pressure
    token: EcoString,
}

let config = Arc::new(SharedConfig {
    host: EcoString::from("api.example.com"),
    token: EcoString::from("s3cr3t"),
});

// 1000 workers: zero heap allocations from cloning
for _ in 0..1000 {
    let c = config.clone();
    spawn_worker(move || {
        let _ = c.host.clone();  // Refcount bump only
        let _ = c.token.clone(); // Refcount bump only
    });
}
```

## Size Comparison

```rust
use std::mem::size_of;

assert_eq!(size_of::<String>(), 24);     // 24 bytes, always heap
assert_eq!(size_of::<EcoString>(), 16);  // 16 bytes, 15 inline
```

## When to Reach for EcoString

| Scenario | `String` | `EcoString` |
|----------|----------|-------------|
| Clone frequently | O(n), allocates | O(1), refcount |
| Cache values | High allocator pressure | Minimal overhead |
| Shared templates | Arc<String> overhead | Inline + refcount |
| Short strings (< 16 bytes) | Heap allocates | Inline, no alloc |
| Hot path mutation | Mutate in place | Copy-on-write alloc |
| FFI / C interop | Works directly | Need `.as_str()` |

## Cargo.toml

```toml
[dependencies]
ecow = "0.3"
```

## See Also

- [mem-compact-string](mem-compact-string.md) — Full compact string trade-off table
- [mem-clone-from](mem-clone-from.md) — `clone_from()` reuse (less critical with EcoString)
- [mem-arc-str](mem-arc-str.md) — `Arc<str>` for thread-shared immutable strings
