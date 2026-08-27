# mem-compact-string

> Consider compact or clone-on-write string types when string representation is a measured memory or allocation bottleneck

## Why It Matters

`String` is an excellent general-purpose owned UTF-8 buffer: it supports growth and exposes familiar capacity semantics. That generality has representation overhead and short strings normally require a separate heap allocation.

Small-string-optimized and clone-on-write crates trade some API and implementation complexity for different storage behavior:

- inline short strings can avoid a heap allocation;
- a smaller owner representation can improve density;
- clone-on-write heap strings can make cloning cheap when mutation is uncommon.

There is no universally best compact string. Representation size, inline capacity, clone cost, mutation behavior, target architecture, and interoperability all matter.

## `compact_str::CompactString`

`CompactString` stores short strings inline and spills longer values to the heap.

```rust
use compact_str::CompactString;

fn main() {
    let short = CompactString::from("hello");
    let long = CompactString::from("x".repeat(100));

    assert_eq!(short.as_str(), "hello");
    assert_eq!(long.len(), 100);
}
```

On common 64-bit targets the crate documents a 24-byte representation with up to 24 inline bytes. Treat that as a crate-version and target property, not a Rust language guarantee.

Formatting directly into a compact string can be useful when it matches the construction pattern:

```rust
use compact_str::format_compact;

fn main() {
    let value = 42;
    let text = format_compact!("value: {value}");
    assert_eq!(text.as_str(), "value: 42");
}
```

## `smartstring::SmartString`

`smartstring` offers inline-or-heap strings with two modes. `LazyCompact` avoids eagerly moving heap strings back inline; `Compact` re-inlines aggressively when values shrink enough.

```rust
use smartstring::{LazyCompact, SmartString};

fn main() {
    let mut value: SmartString<LazyCompact> = "short".into();
    value.push_str(" string");
    assert_eq!(value.as_str(), "short string");
}
```

The crate documents `SmartString` as the same size as `String` and, on 64-bit architectures, an inline capacity of 23 bytes. Those details come from the crate representation, not from Rust itself.

Choose `Compact` only if aggressive re-inlining is desirable; repeatedly crossing the inline/heap boundary can create extra allocation traffic.

## `ecow::EcoString`

`EcoString` combines inline storage with clone-on-write heap storage:

```rust
use ecow::EcoString;

fn main() {
    let original = EcoString::from("a sufficiently long shared string value");
    let mut clone = original.clone();

    assert_eq!(clone, original);
    clone.push_str(" changed");
    assert_ne!(clone, original);
}
```

For normal little-endian 32-bit and 64-bit systems, current `ecow` documents `EcoString` as 16 bytes with 15 bytes of inline storage. The crate explicitly notes a different layout on 64-bit big-endian systems, and its inline limit is semver-exempt. Treat these as version and target properties, not eternal constants.

Heap-backed clones share storage until mutation, so clone-heavy read-mostly workloads can benefit. Inline values are simply small inline data; cheap cloning does not mean mutation is free.

## Inspect Representation Sizes on Supported Targets

```rust
use std::mem::size_of;

use compact_str::CompactString;
use ecow::EcoString;
use smartstring::{LazyCompact, SmartString};

fn main() {
    println!("String: {}", size_of::<String>());
    println!("CompactString: {}", size_of::<CompactString>());
    println!("SmartString: {}", size_of::<SmartString<LazyCompact>>());
    println!("EcoString: {}", size_of::<EcoString>());
}
```

Do not encode platform-specific numbers as unconditional compile-time assertions in a general Rust rule.

## A Smaller Owner Is Not the Whole Memory Story

For a million strings, multiplying `size_of::<T>()` by the count measures only inline owner storage. Total memory can also include:

- heap allocations for spilled strings;
- allocator metadata and slack;
- reference-count headers;
- container capacity;
- duplicated versus shared contents;
- alignment and padding in surrounding structs.

Measure heap or resident memory if total footprint is the goal.

## Keep Representation Choices Behind Ordinary APIs When Practical

```rust
use ecow::EcoString;

struct Record {
    name: EcoString,
}

impl Record {
    pub fn new(name: &str) -> Self {
        Self {
            name: EcoString::from(name),
        }
    }

    pub fn name(&self) -> &str {
        self.name.as_str()
    }
}

fn main() {
    let record = Record::new("Ada");
    assert_eq!(record.name(), "Ada");
}
```

This keeps a niche storage type internal. A real constructor may reasonably take `&str`, `String`, `impl Into<String>`, or another shape depending on ownership and ergonomics; do not mechanically genericize every public string parameter.

## When Compact Strings Fit

Good candidates include:

- very large collections dominated by short owned strings;
- cache keys or AST/token data where locality or allocation count matters;
- clone-heavy read-mostly text where clone-on-write semantics fit;
- workloads where profiling shows `String` representation or allocation is significant.

Ordinary `String` may be better when:

- strings are heavily and repeatedly mutated;
- most strings spill to the heap anyway;
- interoperability and dependency simplicity matter more;
- extra branches or reference counting hurt the hot path;
- measurements show no meaningful benefit.

For immutable fixed-length owned text, also consider `Box<str>`; for shared text, `Arc<str>` may be the clearer ownership model.

## Benchmark the Distribution You Actually Have

Synthetic all-short-string benchmarks can mislead. Use representative length distributions and operation mixes. Measure the dimensions relevant to the motivation:

- allocation count and bytes;
- resident memory or container footprint;
- clone throughput if cloning matters;
- mutation throughput if mutation matters;
- lookup and iteration performance when locality is the goal.

## Cargo.toml

```toml
[dependencies]
compact_str = "0.9"
smartstring = "1"
ecow = "0.3"
```

Pin versions according to your project's dependency policy; representation details can change across crate releases.

## Practical Guidance

- Choose compact strings from workload data, not from a leaderboard of owner sizes.
- Treat inline capacities and layout sizes as crate-version and target properties.
- Distinguish small-string optimization from clone-on-write semantics.
- Keep niche representation types behind ordinary string-oriented API boundaries when practical.
- Measure total allocation and memory effects, not only `size_of`.
- Re-benchmark when crate versions or target architectures change.

## See Also

- [mem-ecow-clone-heavy](./mem-ecow-clone-heavy.md) - Clone-on-write strings
- [mem-boxed-slice](./mem-boxed-slice.md) - `Box<str>` and fixed-size ownership
- [mem-arc-str](./mem-arc-str.md) - Shared string ownership
- [own-cow-conditional](./own-cow-conditional.md) - Borrow-or-own strings
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
