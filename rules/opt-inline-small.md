# opt-inline-small

> Use `#[inline]` selectively, especially when a small non-generic public function benefits from cross-crate inlining.

## Why It Matters

Rust's optimizer already inlines functions when it considers that profitable. `#[inline]` is a hint, not a guarantee that a call disappears.

One place the attribute has a concrete compilation-model role is a **non-generic function used from another crate**: marking it `#[inline]` makes its body available to downstream code generation so the downstream optimizer can consider inlining it.

That does not mean every small function should carry the attribute. Extra body availability can increase compile work and aggressive inlining can increase code size. Use the hint where the API boundary and measurements justify it.

## Bad: Adding `#[inline]` Because a Function Looks Small

<!-- rust-check: compile -->
```rust
fn is_ascii_digit(byte: u8) -> bool {
    byte.is_ascii_digit()
}

fn count_digits(data: &[u8]) -> usize {
    data.iter().filter(|&&byte| is_ascii_digit(byte)).count()
}

assert_eq!(count_digits(b"a1b23"), 3);
```

There is nothing wrong with this code. Same-crate optimization may inline `is_ascii_digit` already. Adding an attribute without checking optimized code or performance would not make it inherently better.

## Good: Use the Hint for a Deliberate Cross-Crate API Case

<!-- rust-check: compile -->
```rust
pub struct Flags(u32);

impl Flags {
    #[inline]
    pub fn contains(&self, mask: u32) -> bool {
        self.0 & mask == mask
    }
}

fn local_consumer(flags: &Flags) -> bool {
    flags.contains(0b0011)
}
```

For a real library, `#[inline]` makes this non-generic method body available to downstream crates for inlining and related optimization. The compiler still decides what actually happens at each call site.

## Inline Modes

<!-- rust-check: compile -->
```rust
#[inline]
fn suggest_inline(x: u32) -> u32 {
    x.wrapping_add(1)
}

#[inline(always)]
fn strongly_suggest_inline(x: u32) -> u32 {
    x.wrapping_add(1)
}

#[inline(never)]
fn suggest_no_inline(x: u32) -> u32 {
    x.wrapping_add(1)
}
```

All three are hints. Do not document them as commands that the compiler must obey.

## Generic Functions Are Different

Generic function bodies are already available where they are instantiated, so they do not need `#[inline]` merely to make cross-crate inlining possible.

<!-- rust-check: compile -->
```rust
pub fn choose_min<T: Ord>(a: T, b: T) -> T {
    if a <= b { a } else { b }
}
```

An explicit hint can still influence a particular optimization decision, but add it for measured behavior rather than as generic-function boilerplate.

## Inlining Is Not a Simple Transitive Rule

Do not teach that every callee in a chain must carry `#[inline]` or else it “cannot” inline. The optimizer considers call graphs and available bodies; outcomes depend on crate boundaries, optimization settings, monomorphization, LTO, code size, and heuristics.

If a particular nested call matters, inspect the optimized output instead of inferring it from attributes alone.

## Function-Call Overhead Is Only Part of the Story

Inlining can remove a call, but its larger value is often exposing the body for follow-on optimizations such as constant propagation, dead-code elimination, or vectorization. Conversely, copying a body into many callers can hurt instruction-cache behavior or binary size.

That is why “tiny function = inline” is weaker guidance than “measured cross-crate hot path = consider inline.”

## LTO Changes the Tradeoff

Link-time optimization can expose more cross-crate code to the optimizer. If a project uses LTO, the marginal value of adding `#[inline]` purely for cross-crate visibility may differ from a non-LTO build.

Measure the release configuration you actually ship.

## Verify the Result

Useful checks include:

- benchmark the affected operation,
- inspect optimized assembly or LLVM IR where necessary,
- compare binary/code-section size,
- test the important release profiles and targets.

Do not infer success from the mere presence of the attribute.

## See Also

- [opt-inline-always-rare](./opt-inline-always-rare.md) - Stronger inline hints
- [opt-inline-never-cold](./opt-inline-never-cold.md) - Keeping cold code separate
- [opt-lto-release](./opt-lto-release.md) - Cross-crate optimization with LTO
- [perf-profile-first](./perf-profile-first.md) - Measure first
