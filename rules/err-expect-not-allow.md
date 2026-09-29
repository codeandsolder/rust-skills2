# err-expect-not-allow

> Prefer narrow, reasoned `#[expect(...)]` for suppressible lints; never use expectations to waive correctness, safety, or panic policy

## Why It Matters

Rust's `expect` lint level records that a specific lint is supposed to fire. When the lint no longer fires, `unfulfilled_lint_expectations` reports the stale suppression.

That makes `#[expect]` useful for narrow exceptions to noisy or context-dependent lints. It is not a general escape hatch: the strict gate rejects expectations for high-signal correctness/safety policy, and broad lint-group expectations hide too much. Compiler lint levels remain `deny` so proc-macro-generated code can use its own internal lint attributes.

This rule concerns the **lint attribute** `#[expect(...)]`, not the panic-producing `Result::expect`/`Option::expect` methods.

## Bad: Permanent Handwritten `allow`

```rust
#[allow(clippy::too_many_lines)]
fn generated_dispatch() {
    // large mechanically generated-looking dispatch table
}

fn main() {}
```

The allowance remains silently even if the function later becomes short enough that no exception is needed.

## Good: Expect One Specific Suppressible Lint

```rust
#[expect(
    clippy::too_many_lines,
    reason = "protocol dispatch table mirrors the wire specification"
)]
fn generated_dispatch() {
    // ...
}

fn main() {}
```

If the function stops triggering `too_many_lines`, `unfulfilled_lint_expectations` tells us to remove the stale attribute.

## Make Stale Expectations Fail CI

```toml
[lints.rust]
unfulfilled_lint_expectations = "deny"
```

The rust-skills2 strict gate rejects handwritten attempts to lower or expect this lint, so stale-expectation checking remains mandatory without breaking proc-macro-generated code.

## Do Not Expect Whole Groups

Avoid broad attributes such as:

```text
#[expect(clippy::pedantic)]
#[expect(clippy::correctness)]
#[expect(warnings)]
```

A group can gain new members as the toolchain changes, silently widening the exception. Name the one concrete lint whose tradeoff was reviewed.

The reusable strict gate rejects group-level expectations in handwritten source.

## Do Not Expect High-Signal Categories

Correctness, suspicious, and performance diagnostics should be fixed rather than locally waived during normal AI development. The reusable gate discovers current group membership from nightly Clippy and rejects handwritten expectations for members of those categories.

Concrete non-negotiable lints such as `unwrap_used`, `expect_used`, explicit `panic`, undocumented unsafe blocks, and lock guards held across `await` are deny-level in Clippy and explicitly blocked from handwritten `#[expect]` by the source-policy precheck.

## Generated Code Is the Main `allow` Exception

Generated source sometimes needs unconditional lint permissions because different targets or generator versions emit different shapes. A generator may emit a reasoned crate/module-level `allow` for style-only lints.

Handwritten source should not copy that pattern. The reusable strict gate source-checks workspace Rust files and rejects handwritten `#[allow(...)]` attributes while leaving build/proc-macro output outside the source tree alone.

## Scope and Fulfillment Matter

An expectation is fulfilled only by a lint emission suppressed by that expectation. Keep it immediately next to the deliberate lint site and explain the design constraint, not the lint name.

Good reasons describe facts such as:

- framework trait shape requires an otherwise-unused async boundary;
- a generated protocol table must stay contiguous for auditability;
- a proc-macro expansion currently triggers a documented false positive.

Bad reasons merely say “Clippy complains” or “needed for CI.”

## Migration Pattern

When replacing a handwritten `allow`:

```text
1. Check whether the code can be improved so no suppression is needed.
2. Identify the one concrete lint that remains unavoidable.
3. Verify that the lint is not part of a non-suppressible policy category.
4. Move the attribute to the smallest practical item.
5. Replace allow with #[expect(lint, reason = "...")].
6. Keep unfulfilled_lint_expectations fatal in CI.
```

## Practical Guidance

- Fix the code before reaching for any suppression.
- Never expect a lint group.
- Never expect correctness/suspicious/perf policy lints.
- Keep `#[expect]` narrow and reasoned for the remaining suppressible lints.
- Reserve `#[allow]` for generated code that cannot use fulfillment semantics.
- For rules that must not be locally waived, keep compiler lint levels at `deny` and let the strict source-policy precheck reject handwritten lowering/suppression attributes.

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) - Avoid panic-producing `expect()`
- [lint-deny-correctness](./lint-deny-correctness.md) - Critical lint policy
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoid panic-style extraction
