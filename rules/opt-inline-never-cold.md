# opt-inline-never-cold

> Use cold-path and inlining annotations as measured optimization hints, not source-level guarantees

## Why It Matters

Large or expensive error paths can increase the amount of code near a hot path. Rust provides `#[cold]`, `#[inline(never)]`, and `core::hint::cold_path()` to communicate optimization intent, but these are **hints**. They do not guarantee a particular branch instruction, section layout, cache behavior, or final machine-code shape.

Start with clear control flow. Add annotations when profiling or generated-code inspection shows that outlining a rare path matters.

## Extract Expensive Rare Work

A helper can keep the common path visually small and gives the compiler a separate function to optimize:

```rust
#[derive(Debug, PartialEq)]
enum DecodeError {
    Empty(String),
}

fn decode(data: &[u8]) -> Result<u8, DecodeError> {
    let Some(&first) = data.first() else {
        return Err(empty_error());
    };
    Ok(first)
}

#[cold]
#[inline(never)]
fn empty_error() -> DecodeError {
    DecodeError::Empty("expected at least one byte".to_owned())
}

fn main() {
    assert_eq!(decode(&[7]), Ok(7));
    assert!(matches!(decode(&[]), Err(DecodeError::Empty(_))));
}
```

`#[cold]` tells the compiler the function is unlikely to be called. `#[inline(never)]` asks it not to inline the function. The Reference defines all forms of `#[inline]` as hints, so do not describe `#[inline(never)]` as an absolute promise that the body can never be duplicated or otherwise transformed.

## `#[cold]` Is Useful for Rare Functions

Error construction and reporting are common candidates when they are genuinely uncommon:

```rust
#[derive(Debug)]
struct ParseFailure {
    input: String,
    message: String,
}

fn parse_positive(input: &str) -> Result<u32, ParseFailure> {
    match input.parse::<u32>() {
        Ok(value) if value > 0 => Ok(value),
        _ => Err(parse_failure(input)),
    }
}

#[cold]
fn parse_failure(input: &str) -> ParseFailure {
    ParseFailure {
        input: input.to_owned(),
        message: "expected a positive integer".to_owned(),
    }
}

fn main() {
    assert_eq!(parse_positive("8").unwrap(), 8);
    let err = parse_positive("0").unwrap_err();
    assert_eq!(err.input, "0");
    assert!(err.message.contains("positive"));
}
```

Do not annotate a path as cold merely because it represents an error. In some workloads, parse failures, cache misses, retries, or validation errors are common enough to be performance-relevant hot paths themselves.

## `cold_path()` Hints About the Current Path

Rust 1.95 stabilized `core::hint::cold_path()`. Calling it tells the compiler that the path containing the call is unlikely to be taken:

```rust
use core::hint::cold_path;

fn checked_get(values: &[u8], index: usize) -> Option<u8> {
    if index >= values.len() {
        cold_path();
        return None;
    }

    Some(values[index])
}

fn main() {
    assert_eq!(checked_get(&[10, 20], 1), Some(20));
    assert_eq!(checked_get(&[10, 20], 4), None);
}
```

This is an optimization hint, not a correctness primitive. The result must be correct even if the compiler ignores the hint or the branch is frequently taken at runtime.

## Do Not Invent `likely()` Semantics

A wrapper built from `cold_path()` can express local intent, but it is not a standardized replacement for every `likely`/`unlikely` intrinsic from other languages. Prefer putting `cold_path()` directly in the genuinely cold branch so the meaning is visible at the call site.

Similarly, an early return is often good code structure, but Rust does not specify that “early return means unlikely.” Do not rely on control-flow shape as a formal branch-probability annotation.

## Panic and Bounds-Error Helpers

Outlining a panic path can be useful in a measured low-level routine:

```rust
fn byte_at(values: &[u8], index: usize) -> u8 {
    match values.get(index) {
        Some(&value) => value,
        None => out_of_bounds(index, values.len()),
    }
}

#[cold]
#[inline(never)]
fn out_of_bounds(index: usize, len: usize) -> ! {
    panic!("index {index} out of bounds for length {len}");
}

fn main() {
    assert_eq!(byte_at(&[3, 4], 0), 3);
}
```

For ordinary indexing, prefer the standard library's existing checked/indexing behavior. A custom helper is worthwhile only when it serves an actual API or measured code-generation goal.

## When Not to Annotate

Avoid scattering `#[cold]` or `#[inline(never)]` over code when:

- the path frequency is unknown;
- the function is tiny and the compiler already optimizes it well;
- the code is not performance-sensitive;
- the annotation makes generated code worse on important targets;
- a clearer algorithmic or allocation fix has much larger impact.

## Verify the Result

For optimization work, compare representative benchmarks and inspect generated assembly/IR when necessary. Attribute semantics are intentionally weaker than “this exact machine-code transformation will happen.”

## Practical Guidance

- Keep rare expensive work in a separate helper when that improves clarity or measured code layout.
- Use `#[cold]` to mark a genuinely rarely called function.
- Use `#[inline(never)]` sparingly and remember it is a hint.
- Use `core::hint::cold_path()` for a stable path-level cold hint on Rust 1.95+.
- Never make correctness depend on a branch or inlining hint.
- Measure before and after; remove annotations that do not help.

## See Also

- [opt-inline-small](./opt-inline-small.md) - Inlining small hot functions
- [opt-inline-always-rare](./opt-inline-always-rare.md) - Forced-inlining trade-offs
- [perf-profile-first](./perf-profile-first.md) - Profile before optimizing
