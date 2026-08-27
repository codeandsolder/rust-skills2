# err-expect-not-allow

> Prefer `#[expect(...)]` when you are suppressing a lint that should currently fire and want stale suppressions detected

## Why It Matters

Rust 1.81 stabilized the `expect` lint level. `#[expect(lint_name)]` suppresses an expected lint emission **and records that the emission is supposed to exist**. If the lint would no longer fire, the compiler emits `unfulfilled_lint_expectations` at the attribute.

That makes `#[expect]` a strong default for targeted suppressions during refactoring or for deliberate exceptions whose justification depends on the current code actually triggering a lint.

`#[allow]` is not obsolete. It is appropriate when the policy is “this lint is permitted here whether or not the current configuration/code shape happens to trigger it.”

## Bad: A Stale `allow` Is Silent

```rust
#[allow(unused_variables)]
fn process() {
    let value = 42;
    println!("{value}");
}

fn main() {
    process();
}
```

The function no longer has an unused variable, but the `allow` remains silently. That may be fine if the scope intentionally permits unused variables; it is poor if the annotation was meant to excuse one specific current warning.

## Good: Expect the Specific Current Lint

```rust
#[expect(unused_variables, reason = "placeholder kept for the next migration step")]
fn process() {
    let future_value = 42;
}

fn main() {
    process();
}
```

The expectation is fulfilled because `unused_variables` would otherwise be emitted and is suppressed by this `expect`.

## What Happens When the Lint Disappears

If the code later becomes:

```text
#[expect(unused_variables, reason = "placeholder kept for the next migration step")]
fn process() {
    let future_value = 42;
    println!("{future_value}");
}
```

then `unused_variables` no longer fires. Rust emits the `unfulfilled_lint_expectations` lint with a diagnostic such as `this lint expectation is unfulfilled`.

The stale expectation is the warning; the original lint is **not** described as “fulfilled” after it disappears.

## The Lint Name Is `unfulfilled_lint_expectations`

To make stale expectations fail CI, raise that compiler lint:

```toml
[lints.rust]
unfulfilled_lint_expectations = "deny"
```

There is no compiler lint named `fulfill_expectations` for this purpose.

## Clippy Expectations

`expect` also works with tool lints when the tool is running:

```rust
#[expect(
    clippy::unwrap_used,
    reason = "validated nonempty input is an invariant at this boundary"
)]
fn first(values: &[u8]) -> u8 {
    *values.first().unwrap()
}

fn main() {
    assert_eq!(first(&[3]), 3);
}
```

When Clippy evaluates this code, the expectation is useful only if `clippy::unwrap_used` is enabled at a level that would otherwise emit there.

Rust 1.81 also stabilized lint `reason = "..."` syntax. Give suppressions concise reasons that explain the exceptional design decision rather than restating the lint name.

## When `#[allow]` Is Better

Use `allow` when you intentionally permit a lint in a scope and do **not** require a current violation to exist. Common examples include configuration-dependent code where some targets trigger the lint and others do not, generated code, or a module whose policy deliberately differs from the crate default.

```rust
#[allow(dead_code, reason = "platform hooks are selected by cfg in downstream builds")]
mod platform_hooks {
    pub fn unix_hook() {}
    pub fn windows_hook() {}
}

fn main() {}
```

Using `expect(dead_code)` mechanically here could create unfulfilled expectations on configurations where an item becomes used.

## Scope and Fulfillment Matter

An expectation is fulfilled only by a lint emission suppressed by that expectation. A nested `#[allow]`, `#[warn]`, or another more-local `#[expect]` can change which attribute handles the lint. Do not treat an outer `expect` as a simple assertion that “somewhere below here this lint exists.”

When the exact scope matters, put the expectation as close as practical to the deliberate lint site.

## `forbid` Is Different

`#[forbid(lint)]` is deliberately stronger than `deny`: descendant scopes cannot lower that lint with `allow` or `expect`. If a crate chooses `forbid`, a local expectation is not an escape hatch.

## Migration Pattern

When replacing a targeted `allow`:

```text
1. Confirm which concrete lint the annotation is suppressing.
2. Move the suppression close to the intentional lint site if practical.
3. Replace `allow` with `expect` and record the reason.
4. Enable or deny `unfulfilled_lint_expectations` in CI if stale suppressions must fail the build.
5. Keep `allow` when unconditional permission, rather than current fulfillment, is the actual policy.
```

Clippy's `allow_attributes` restriction lint can help projects migrate ordinary `#[allow(...)]` attributes toward `#[expect(...)]` where that policy is desired.

## Practical Guidance

- Use `expect` for a suppression whose continued existence should be checked.
- Use `allow` for an intentionally permissive scope where no current emission is required.
- Name `unfulfilled_lint_expectations` when configuring stale-expectation enforcement.
- Include a `reason` that explains the exception.
- Keep expectations narrow enough that it is clear what fulfills them.

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) - Justified uses of `expect()`
- [lint-deny-correctness](./lint-deny-correctness.md) - Lint-level policy
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Handling unwrap/expect policies
