# mem-ecow-clone-heavy

> Consider `EcoString` for clone-heavy immutable-or-COW strings

**Rule**: `mem-ecow-clone-heavy`

## Why It Matters

`EcoString` from `ecow` combines small-string inline storage with clone-on-write heap storage. Short strings fit directly in the value. Longer strings spill into a reference-counted `EcoVec<u8>` allocation; cloning a spilled string shares that allocation, and mutation copies only when the allocation is shared.

This can be attractive for parsers, caches, syntax trees, templates, or configuration structures where strings are cloned frequently and mutated relatively rarely. It is a workload trade-off, not a blanket replacement for `String`.

As of August 2026, `ecow` 0.3.0 is current.

## Bad

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

#[derive(Clone)]
struct Template {
    name: String,
    content: String,
}

struct TemplateCache {
    templates: HashMap<String, Template>,
}

fn render_copy(cache: &TemplateCache, name: &str) -> Option<String> {
    let template = cache.templates.get(name)?;

    // These String clones duplicate the owned string contents.
    let copied_name = template.name.clone();
    let copied_content = template.content.clone();
    Some(format!("Rendering: {copied_name} with {copied_content}"))
}
```

This is not inherently wrong. If the caller really needs independent mutable `String`s, ordinary `String` may be the simpler representation.

## Good

<!-- rust-check: compile -->
```rust
use ecow::EcoString;
use std::collections::HashMap;

#[derive(Clone)]
struct Template {
    name: EcoString,
    content: EcoString,
}

struct TemplateCache {
    templates: HashMap<EcoString, Template>,
}

fn clone_template(cache: &TemplateCache, name: &str) -> Option<Template> {
    // Inline strings copy their bounded inline representation. Spilled strings
    // share their reference-counted allocation until one copy is mutated.
    cache.templates.get(name).cloned()
}

let mut cache = TemplateCache { templates: HashMap::new() };
cache.templates.insert(
    EcoString::from("welcome"),
    Template {
        name: EcoString::from("welcome"),
        content: EcoString::from("Welcome to a sufficiently long shared template body"),
    },
);

let cloned = clone_template(&cache, "welcome").unwrap();
assert_eq!(cloned.name, "welcome");
```

## Clone-on-Write Behavior

```rust
use ecow::EcoString;

let original = EcoString::from("a string long enough to use shared heap storage");
let mut copy = original.clone();
assert_eq!(copy, original);

// Mutating one shared heap-backed copy detaches it as needed.
copy.push('!');
assert_ne!(copy, original);
assert_eq!(original, "a string long enough to use shared heap storage");
```

Do not describe every `EcoString::clone()` as a refcount bump. Inline values are copied inline; heap-backed values share reference-counted storage. Both are cheap, but for different reasons.

## Layout Is Target-Dependent

```rust
use ecow::EcoString;
use std::mem::size_of;

let value_size = size_of::<EcoString>();
let inline_limit = EcoString::INLINE_LIMIT;
assert!(value_size > 0);
assert!(inline_limit > 0);
```

On ordinary 32-bit and 64-bit little-endian targets, the current crate documents a 16-byte `EcoString` with 15 bytes of inline storage. The crate also documents different values on 64-bit big-endian systems, and `INLINE_LIMIT` is semver-exempt. Prefer `EcoString::INLINE_LIMIT` when code genuinely needs the current inline threshold instead of hard-coding 15.

## When to Reach for EcoString

| Workload | `String` | `EcoString` |
|----------|----------|-------------|
| Frequent cloning of long strings | Duplicates owned contents | Heap-backed clones share storage |
| Many short strings | Simple standard type | Inline storage may avoid allocation |
| Heavy in-place mutation | Usually straightforward | COW may detach shared storage |
| Public API interoperability | Ubiquitous | Often expose `&str` at boundaries |

Measure real memory/allocation behavior when the choice matters. Representation size, string-length distribution, clone rate, and mutation rate all affect the result.

## Cargo.toml

```toml
[dependencies]
ecow = "0.3"
```

## See Also

- [mem-compact-string](mem-compact-string.md) - Compact string trade-offs
- [mem-clone-from](mem-clone-from.md) - Reusing owned buffers
- [mem-arc-str](mem-arc-str.md) - `Arc<str>` for immutable shared strings
