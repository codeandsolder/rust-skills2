# lint-warn-complexity

**Rule**: `lint-warn-complexity`

> Enable `clippy::complexity` to catch needlessly complicated expressions and operations

## Why It Matters

`clippy::complexity` is one of Clippy's default warning groups. Its lints target code that performs unnecessary operations or expresses a simple computation in a more complicated way than needed.

The group is not a general measurement of “cognitive complexity,” and it does not contain every lint that can make code shorter. Clippy assigns each lint to a primary group such as `complexity`, `style`, `perf`, `suspicious`, or `correctness`; use the current Clippy documentation when group membership matters.

## Configuration

At crate level:

```rust
#![warn(clippy::complexity)]

fn main() {}
```

Or with Cargo lint configuration:

```toml
[lints.clippy]
complexity = "warn"
```

`cargo clippy` must actually run for Clippy lints to be evaluated. `cargo check` alone does not execute Clippy.

## `clone_on_copy`

Calling `clone()` on a concrete `Copy` value performs an unnecessary explicit clone operation. `clone_on_copy` belongs to the complexity group:

```rust
fn main() {
    let value = 42_u64;
    let copied = value.clone();
    assert_eq!(copied, 42);
}
```

Clippy can simplify this to:

```rust
fn main() {
    let value = 42_u64;
    let copied = value;
    assert_eq!(copied, 42);
}
```

This does **not** mean `Clone::clone` is bad on `Copy` values in generic code. The lint targets needless concrete use where an ordinary copy expresses the operation directly.

## `bind_instead_of_map`

Mapping a successful `Option`/`Result` value by wrapping it immediately back into the same container is more directly expressed with `map`:

```rust
fn add_one(input: Option<i32>) -> Option<i32> {
    input.and_then(|value| Some(value + 1))
}

fn main() {
    assert_eq!(add_one(Some(2)), Some(3));
}
```

Prefer:

```rust
fn add_one(input: Option<i32>) -> Option<i32> {
    input.map(|value| value + 1)
}

fn main() {
    assert_eq!(add_one(Some(2)), Some(3));
}
```

The shorter form also states the semantics more accurately: this operation transforms a present value; it does not conditionally flatten another `Option`.

## `needless_question_mark`

Wrapping an expression in `Some(expr?)` or `Ok(expr?)` at the end of a function can be redundant when no conversion is needed:

```rust
fn find_x(input: &str) -> Option<usize> {
    Some(input.find('x')?)
}

fn main() {
    assert_eq!(find_x("abcx"), Some(3));
}
```

Prefer the value directly:

```rust
fn find_x(input: &str) -> Option<usize> {
    input.find('x')
}

fn main() {
    assert_eq!(find_x("abcx"), Some(3));
}
```

Do not apply this rewrite mechanically when `?` is performing an error conversion required by the function's return type.

## `unnecessary_cast`

Casting a value to the type it already has adds noise and can hide the casts that actually matter:

```rust
fn doubled(value: u32) -> u32 {
    (value as u32) * 2
}

fn main() {
    assert_eq!(doubled(3), 6);
}
```

The cast can be removed:

```rust
fn doubled(value: u32) -> u32 {
    value * 2
}

fn main() {
    assert_eq!(doubled(3), 6);
}
```

## Complexity Is Not the Same as Allocation or Performance

A construct can be wasteful without belonging to the `complexity` group. For example, needless intermediate allocation may be caught by a `perf` lint, another Clippy group, or no lint at all depending on the exact code.

Likewise, this rule should not claim that every `format!("literal")`, boxed return value, or filtered iterator is inherently a complexity warning. Verify the concrete lint rather than assigning examples to a group by intuition.

## Clippy Suggestions Are Starting Points

Many complexity lints have machine-applicable suggestions, but the simplified form can still affect readability, inference, borrow lifetimes, or an API's intentional explicitness. Review changes produced by `cargo clippy --fix` just as you would compiler edition fixes.

A local exception can be justified when clarity is genuinely better in the flagged form:

```rust
#[expect(
    clippy::clone_on_copy,
    reason = "mirrors the generic Clone-based example immediately above"
)]
fn documentation_example(value: u32) -> u32 {
    value.clone()
}

fn main() {
    assert_eq!(documentation_example(5), 5);
}
```

Prefer `#[expect]` for a targeted suppression that should become stale when the lint stops firing; use `#[allow]` when unconditional permission in the scope is the real policy.

## Language Features Are Separate

Edition 2024 let chains are a Rust language feature, not a member of `clippy::complexity`. They may make some nested conditions clearer, but enabling the Clippy group does not enable the syntax and changing editions does not change which lint group a warning belongs to.

Similarly, match guards and `if let` guards are language constructs. Discuss them when they improve a particular rewrite, not as “notable lints” in this group.

## Practical Guidance

- Enable `clippy::complexity` unless the project has a deliberate reason not to use Clippy's default warning groups.
- Run `cargo clippy --all-targets --all-features` in CI when those configurations are supported.
- Review the named lint before documenting why a piece of code is warned on.
- Do not equate shorter code with better code; preserve clarity and required semantics.
- Keep Clippy group guidance separate from Rust edition migration guidance.

## References

- [Clippy lint index](https://rust-lang.github.io/rust-clippy/master/index.html)
- [Clippy lint groups](https://doc.rust-lang.org/clippy/lints.html)

## See Also

- [lint-warn-style](./lint-warn-style.md) — Idiom/style warnings
- [lint-warn-perf](./lint-warn-perf.md) — Performance warnings
- [lint-pedantic-selective](./lint-pedantic-selective.md) — Opt-in pedantic lints
- [lint-edition-2024](./lint-edition-2024.md) — Rust 2024 migration lints
