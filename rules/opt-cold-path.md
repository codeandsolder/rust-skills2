# opt-cold-path

> Use `core::hint::cold_path()` to describe a measured unlikely path without extracting a function just to attach an attribute (Rust 1.95+)

## Why It Matters

The compiler may optimize other paths at the expense of a path reaching
`cold_path()`. It is a suggestion about workload frequency, not a statement
that the path cannot execute. It is available inside a function and in const
contexts.

## Bad: Extracting Code Only for a Hint

```rust
fn process(value: i32) -> Option<i32> {
    if value < 0 {
        return negative();
    }
    Some(value)
}

#[cold]
fn negative() -> Option<i32> {
    None
}
```

The helper may be appropriate when it has its own semantics; this example
extracts it only to place an attribute.

## Good: Mark the Actual Rare Path

```rust
fn process(value: i32) -> Option<i32> {
    if value < 0 {
        core::hint::cold_path();
        return None;
    }
    Some(value)
}
```

The negative case must actually be uncommon in the intended workload.

## Other Valid Uses

- Mark an uncommon fallback, provided it is unusual on the actual deployment hardware.
- Mark a branch that rarely matches in a long search, if measurements support that assumption.
- Use `#[cold]` on a meaningful reusable helper when calls to the helper are uncommon.
- Evaluate `#[inline(never)]` separately; its purpose is different.

Do not mark every early return, error, match or loop termination as cold.
A path inside a debug-only assertion cannot influence the corresponding
release build when that assertion is not evaluated.

## Performance Impact

There is no guaranteed percentage improvement or specific section
placement, including a dedicated `.cold` section. The compiler may change
layout, branch weights, or other optimization decisions. Compare optimized
code and representative benchmark results with and without the hint.

For direct Boolean hints in nightly, see [opt-likely-hint](./opt-likely-hint.md).
There is no need to maintain redundant stable wrappers when the inline
`cold_path()` form is sufficient.

## See Also

- [opt-cold-unlikely](./opt-cold-unlikely.md) — function-level cold hints
- [opt-inline-never-cold](./opt-inline-never-cold.md) — separate inlining policy
- [opt-likely-hint](./opt-likely-hint.md) — Boolean hint APIs
- [perf-hint-apis](./perf-hint-apis.md) — exact contracts
