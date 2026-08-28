# opt-inline-always-rare

> Treat `#[inline(always)]` as a strong optimization hint, not a command; use it only when measurement justifies it.

## Why It Matters

All Rust inline attributes are hints. `#[inline(always)]` strongly suggests inlining at every call site, but the compiler may still ignore it. Forcing the optimizer toward more inlining can increase code size and instruction-cache pressure, and may make performance worse even when a function is tiny.

Rust already performs automatic inlining. Start without `inline(always)` and add it only when a representative benchmark or profile shows a benefit that survives across the builds/targets you care about.

## Bad: Blanket Forced-Inline Hints

<!-- rust-check: compile -->
```rust
struct User {
    name: String,
}

impl User {
    #[inline(always)]
    fn name(&self) -> &str {
        &self.name
    }
}

#[inline(always)]
fn calculate_tax(amount: f64) -> f64 {
    amount * 0.1
}

#[inline(always)]
fn helper(x: i32) -> i32 {
    x + 1
}
```

This is valid Rust. The problem is that the attributes encode a performance opinion without evidence and duplicate work the optimizer already performs.

## Good: Default Heuristics First

<!-- rust-check: compile -->
```rust
use std::hash::Hasher;

struct CounterHasher(u64);

impl Hasher for CounterHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        self.0 = self.0.wrapping_add(bytes.len() as u64);
    }
}

fn calculate_tax(amount: f64) -> f64 {
    amount * 0.1
}
```

Only add `#[inline(always)]` to a measured hot helper when comparison shows that this stronger hint improves the real workload.

## The Three Inline Modes Are Hints

<!-- rust-check: compile -->
```rust
#[inline]
fn suggest_inline(x: i32) -> i32 {
    x + 1
}

#[inline(always)]
fn strongly_suggest_inline(x: i32) -> i32 {
    x + 1
}

#[inline(never)]
fn suggest_no_inline(x: i32) -> i32 {
    x + 1
}
```

The Rust Reference explicitly says the compiler may ignore **every** form. Avoid wording such as “forces inlining” or “prevents inlining” as a language guarantee.

## Generic Functions Usually Do Not Need `#[inline]` for Body Availability

A common misconception is that generic library functions need `#[inline]` so downstream crates can see their bodies. Generic functions are instantiated in crates that use them, so their bodies are already available for optimization there.

<!-- rust-check: compile -->
```rust
pub fn generic_min<T: Ord>(a: T, b: T) -> T {
    if a <= b { a } else { b }
}
```

An inline hint can still affect optimizer decisions in a particular case, but “generic therefore add `#[inline]`” is not a sound rule.

For **non-generic** public functions, `#[inline]` can matter across crate boundaries because it makes the body available for downstream inlining. That is one of the better reasons to consider the ordinary `#[inline]` hint.

## When `#[inline(always)]` May Be Worth Testing

Candidates are usually:

- very small helpers on a proven hot path,
- wrappers where exposing the body enables important constant propagation or vectorization,
- target-specific low-level code where emitted code has been inspected,
- cases where ordinary `#[inline]` or no attribute benchmarked worse.

None of these categories proves a benefit. Measure the exact call pattern.

## Cold and Always-Inline Hints Point in Different Directions

`#[cold]` says a function is unlikely to be called. `#[inline(always)]` says inline expansion should always be attempted. Combining them communicates contradictory optimization intent and should require unusually strong evidence.

Do not rely on whether a particular compiler version warns about the combination; the design smell exists independently of a lint.

## Verify Rather Than Assume

For an inline change, compare:

- benchmark results before/after,
- whole-binary or hot-section size when relevant,
- generated assembly for the actual optimized build,
- more than one important target if the project ships several.

An annotation that helps one microbenchmark but bloats many cold call sites can still lose overall.

## See Also

- [opt-inline-small](./opt-inline-small.md) - Ordinary cross-crate inline hints
- [opt-inline-never-cold](./opt-inline-never-cold.md) - Keeping rare code out of hot callers
- [perf-profile-first](./perf-profile-first.md) - Evidence-driven optimization
