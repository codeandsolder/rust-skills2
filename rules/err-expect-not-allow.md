# err-expect-not-allow

> Prefer narrow, reasoned `#[expect(...)]` when a suppressible lint reliably fires; use a narrow reasoned `#[allow(...)]` only when lint activation is configuration-dependent and fulfillment semantics cannot work

## Why It Matters

Rust's `expect` lint level records that a specific lint is supposed to fire. When the lint no longer fires, `unfulfilled_lint_expectations` reports the stale suppression. That makes `#[expect]` the best default for deliberate exceptions to suppressible lints.

There is one important limit: rustc still parses expectations for Clippy lints even when Clippy is not running. A Clippy lint that legitimately fires only under some feature/target configurations can therefore make plain rustc report an unfulfilled expectation. Wrapping the expectation in `cfg(clippy)` is not a clean workaround because Clippy diagnoses that pattern as `unnecessary_clippy_cfg`.

For those genuinely configuration-dependent cases, a **single-lint, reasoned `#[allow]`** is the stable mechanism. The rust-skills2 strict gate permits that narrow form while continuing to reject unreasoned allowances, lint groups, and high-risk correctness/safety/panic-policy suppressions.

This rule concerns lint attributes, not the panic-producing `Result::expect` / `Option::expect` methods.

## First Choice: Fix the Code

Do not add a suppression merely because CI is strict. First check whether the code can be made clearer or more correct so the lint disappears naturally.

## Preferred: Expect One Specific Suppressible Lint

```rust
#[expect(
    clippy::too_many_lines,
    reason = "protocol dispatch table mirrors the wire specification"
)]
fn protocol_dispatch() {
    // ...
}
```

Use `#[expect]` when the lint should reliably fire in every configuration where the item is compiled. If the code later stops triggering the lint, CI tells us to remove the stale exception.

## Configuration-Dependent Exception: Reasoned Allow

```rust
#[allow(
    clippy::struct_field_names,
    reason = "public field names mirror the published wire schema"
)]
pub struct TupleAssigned {
    pub tuple_id: String,
    pub tuple_local: String,
    pub tuple_remote: String,
}
```

A reasoned `#[allow]` is appropriate when all of the following are true:

- the code itself should not change merely to satisfy the lint;
- the lint is in a suppressible category;
- the exception is one concrete lint, not a lint group;
- lint activation genuinely varies by feature, target, or other compile configuration, so `#[expect]` would become spuriously unfulfilled;
- the reason states the durable API/schema/design constraint.

Typical examples are established public API signatures and externally defined schema field names.

## Why `cfg(clippy)` Is Not the Escape Hatch

Avoid this pattern:

```text
#[cfg_attr(
    clippy,
    expect(
        clippy::struct_field_names,
        reason = "schema names"
    )
)]
```

Clippy itself reports Clippy-lint expectations hidden behind `cfg(clippy)` as `unnecessary_clippy_cfg`. If the lint is genuinely configuration-dependent, use the narrow reasoned `#[allow]` form instead.

## Keep Stale Expectations Fatal

```toml
[lints.rust]
unfulfilled_lint_expectations = "deny"
```

Do not suppress `unfulfilled_lint_expectations` to make a conditional Clippy expectation compile. That defeats the main value of `#[expect]`.

## Do Not Suppress Whole Groups

Avoid broad attributes such as:

```text
#[expect(clippy::pedantic)]
#[allow(clippy::correctness, reason = "...")]
#[allow(warnings, reason = "...")]
```

A group can gain new members as the toolchain changes and silently widen the exception. Name one concrete lint whose tradeoff was reviewed.

The reusable strict gate rejects group-level handwritten suppressions.

## Do Not Suppress High-Signal Categories

Correctness, suspicious, and performance diagnostics should normally be fixed rather than waived. The reusable gate discovers current Clippy group membership and rejects handwritten suppressions for members of those categories, except explicitly policy-approved measured cases such as the existing `large_enum_variant` performance exception.

Concrete non-negotiable lints such as `unwrap_used`, `expect_used`, explicit `panic`, undocumented unsafe blocks, and lock guards held across `await` remain blocked from both `#[expect]` and `#[allow]`.

## Generated Code

Generated source may still need broader unconditional lint control because target or generator versions can emit different shapes. Keep generated-code lint boundaries explicit and machine-verifiable rather than copying generated-code suppression patterns into handwritten source.

## Migration Pattern

When reviewing an existing handwritten suppression:

```text
1. Fix the code if the lint points to a real improvement.
2. Identify the one concrete lint that remains unavoidable.
3. Verify that the lint is not in a non-suppressible policy category.
4. Keep the attribute at the smallest practical item.
5. Use #[expect(lint, reason = "...")] when the lint reliably fires.
6. If fulfillment varies legitimately by compile configuration, use
   #[allow(lint, reason = "...")] instead.
7. Keep unfulfilled_lint_expectations fatal.
```

## Practical Guidance

- Fix before suppressing.
- Never suppress a lint group.
- Never suppress correctness/suspicious/high-risk safety or panic policy lints.
- Prefer `#[expect]` because stale exceptions self-report.
- Use reasoned `#[allow]` only for narrow configuration-dependent exceptions where `#[expect]` cannot have stable fulfillment semantics.
- A reason should describe the API, schema, compatibility, or measured design constraint—not “Clippy complains” or “needed for CI.”

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) - Avoid panic-producing `expect()`
- [lint-deny-correctness](./lint-deny-correctness.md) - Critical lint policy
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoid panic-style extraction
