# lint-warn-style

**Rule**: `lint-warn-style`

> Enable `clippy::style` for established Rust idioms, while treating its suggestions as reviewable guidance rather than formatting law

## Why It Matters

`clippy::style` is one of Clippy's default warning groups. Its lints identify code that is valid but is usually clearer when written with common Rust idioms: `is_empty()` instead of `len() == 0`, `?` instead of propagation boilerplate, direct iteration instead of indexing by range, and so on.

Style lints are not rustfmt, and they are not the Rust compiler's Edition migration lints. Keep those concerns separate:

- **rustfmt** controls source formatting;
- **Clippy `style`** suggests idiomatic source patterns;
- **rustc compatibility lints** warn about language/edition semantic changes.

## Configuration

At crate level:

```rust
#![warn(clippy::style)]

fn main() {}
```

Or in `Cargo.toml`:

```toml
[lints.clippy]
style = "warn"
```

These lints run under `cargo clippy`; `cargo check` by itself does not execute Clippy.

## `len_zero`

When a type provides `is_empty()`, using it directly communicates the intent more clearly than comparing `len()` with zero:

```rust
fn empty(values: &[u8]) -> bool {
    values.len() == 0
}

fn main() {
    assert!(empty(&[]));
}
```

Prefer:

```rust
fn empty(values: &[u8]) -> bool {
    values.is_empty()
}

fn main() {
    assert!(empty(&[]));
}
```

## `needless_return`

Rust functions return the final expression of a block, so an explicit `return` at the end is usually unnecessary:

```rust
fn answer() -> u32 {
    return 42;
}

fn main() {
    assert_eq!(answer(), 42);
}
```

Prefer:

```rust
fn answer() -> u32 {
    42
}

fn main() {
    assert_eq!(answer(), 42);
}
```

Early returns are a different matter. `return Err(...)`, guard-clause returns, and other control-flow exits can be the clearest form and are not equivalent to a needless final `return`.

## `question_mark`

Propagation boilerplate can often be expressed directly with `?`:

```rust
fn first(values: &[u8]) -> Option<u8> {
    let value = match values.first() {
        Some(value) => value,
        None => return None,
    };
    Some(*value)
}

fn main() {
    assert_eq!(first(&[9]), Some(9));
}
```

Prefer:

```rust
fn first(values: &[u8]) -> Option<u8> {
    let value = values.first()?;
    Some(*value)
}

fn main() {
    assert_eq!(first(&[9]), Some(9));
}
```

This lint is about an equivalent propagation idiom, not about forcing `?` into every function that returns `Result` or `Option`.

## `single_match`

A `match` used only to act on one pattern can often be clearer as `if let`:

```rust
fn print_present(value: Option<u32>) {
    match value {
        Some(value) => println!("{value}"),
        None => {}
    }
}

fn main() {
    print_present(Some(3));
}
```

Prefer:

```rust
fn print_present(value: Option<u32>) {
    if let Some(value) = value {
        println!("{value}");
    }
}

fn main() {
    print_present(Some(3));
}
```

If both arms carry meaningful logic, `match` may still be the better construct.

## `needless_range_loop`

Indexing a collection with a loop variable that exists only to retrieve each element obscures direct iteration:

```rust
fn sum(values: &[u32]) -> u32 {
    let mut total = 0;
    for index in 0..values.len() {
        total += values[index];
    }
    total
}

fn main() {
    assert_eq!(sum(&[1, 2, 3]), 6);
}
```

Prefer direct iteration:

```rust
fn sum(values: &[u32]) -> u32 {
    let mut total = 0;
    for value in values {
        total += *value;
    }
    total
}

fn main() {
    assert_eq!(sum(&[1, 2, 3]), 6);
}
```

An index is still appropriate when the position itself matters or when coordinating multiple collections.

## `redundant_closure`

When a closure does nothing except call a function with the same argument shape, passing the function directly is usually clearer:

```rust
fn square(value: i32) -> i32 {
    value * value
}

fn squares(values: &[i32]) -> Vec<i32> {
    values.iter().copied().map(|value| square(value)).collect()
}

fn main() {
    assert_eq!(squares(&[2, 3]), vec![4, 9]);
}
```

Prefer:

```rust
fn square(value: i32) -> i32 {
    value * value
}

fn squares(values: &[i32]) -> Vec<i32> {
    values.iter().copied().map(square).collect()
}

fn main() {
    assert_eq!(squares(&[2, 3]), vec![4, 9]);
}
```

Closures remain useful when they adapt arguments, capture environment, add instrumentation, or otherwise do more than forwarding.

## Do Not Mix rustc Lints into `clippy::style`

`unsafe_op_in_unsafe_fn`, `keyword_idents_2024`, `if_let_rescope`, and similar migration lints are rustc lints, not Clippy style lints. Their default levels and behavior are controlled by rustc and the edition, not by `#![warn(clippy::style)]`.

Likewise, an ordinary compiler lint such as `irrefutable_let_patterns` should not be presented as a new member of the Clippy style group merely because its diagnostic concerns source shape.

See [lint-edition-2024](./lint-edition-2024.md) for Edition migration guidance.

## Group Membership Is Data, Not Intuition

A pattern can look “stylistic” while Clippy classifies its lint as `complexity`, `perf`, `suspicious`, `pedantic`, or another group. For example, `clone_on_copy` is in `clippy::complexity`, not `clippy::style`.

When documenting a specific lint, check the current Clippy lint index rather than guessing from its name or recommendation.

## Selective Exceptions

A project can locally suppress a style lint when the flagged form is intentionally clearer:

```rust
#[expect(
    clippy::needless_return,
    reason = "explicit return mirrors the generated pseudocode in the protocol spec"
)]
fn protocol_example() -> u32 {
    return 7;
}

fn main() {
    assert_eq!(protocol_example(), 7);
}
```

Use narrow exceptions with an explanation. Do not disable the whole style group because one lint conflicts with a local convention; configure that lint specifically instead.

## Practical Guidance

- Keep `clippy::style` enabled as a baseline for normal Rust code.
- Run Clippy on the targets/features that matter to the project.
- Review fixes for semantic or readability changes before applying them wholesale.
- Configure disputed lints individually instead of disabling the group.
- Do not confuse Clippy style guidance with rustfmt or Edition migration lints.
- Check current group membership before teaching a named lint as part of `style`.

## References

- [Clippy lint index](https://rust-lang.github.io/rust-clippy/master/index.html)
- [Clippy lint groups](https://doc.rust-lang.org/clippy/lints.html)

## See Also

- [lint-warn-complexity](./lint-warn-complexity.md) — Complexity warnings
- [lint-warn-suspicious](./lint-warn-suspicious.md) — Suspicious-code warnings
- [lint-rustfmt-check](./lint-rustfmt-check.md) — Formatting checks
- [lint-edition-2024](./lint-edition-2024.md) — Edition migration lints
