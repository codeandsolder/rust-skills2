# err-expect-not-allow

> Use narrow, reasoned `#[expect(...)]` for deliberate suppressible-lint exceptions; handwritten `#[allow(...)]`, Cargo lint levels set to `allow`, and `-A` / `--allow` compiler flags are prohibited by the strict policy

## Why It Matters

Rust's `expect` lint level records that a specific lint is supposed to fire. When the lint stops firing, `unfulfilled_lint_expectations` turns the stale exception into a build failure. That gives every handwritten lint exception an automatic removal signal instead of leaving permanent permission for future warnings.

`#[allow]` has no equivalent expiry mechanism. A crate-, module-, or item-level allow can quietly outlive the condition that justified it, and Cargo or command-line allow levels are broader still. The rust-skills2 strict gate therefore treats unconditional lint permission as generated-code machinery, not as a handwritten-code escape hatch.

This rule concerns lint attributes, not the panic-producing `Result::expect` / `Option::expect` methods.

## First Choice: Fix the Code

Do not add an expectation merely because CI is strict. First check whether the diagnostic identifies a real correctness, API, performance, ownership, or clarity improvement. Suppress only a lint whose tradeoff has been reviewed and whose category is policy-suppressible.

## Handwritten Exception: Expect One Specific Lint

```rust
#[expect(
    clippy::too_many_lines,
    reason = "protocol dispatch table mirrors the wire specification"
)]
fn protocol_dispatch() {
    // ...
}
```

Keep the expectation on the smallest practical item. The reason should state the durable API, schema, compatibility, or measured design constraint—not “Clippy complains” or “needed for CI.”

## Configuration-Dependent Exceptions

Put the expectation behind the **real condition that makes the exception valid**, rather than making the permission unconditional:

```rust
#[cfg_attr(
    feature = "legacy-wire",
    expect(
        clippy::struct_field_names,
        reason = "legacy-wire exposes field names fixed by the external schema"
    )
)]
pub struct WireTuple {
    pub tuple_id: u64,
    pub tuple_local: u64,
    pub tuple_remote: u64,
}
```

Use this only when that lint actually varies with the named feature/target/configuration. If the lint fires in every configuration where the item exists, use an ordinary `#[expect]`.

Do not use `cfg(clippy)` merely to hide an expectation from rustc. Clippy diagnoses that pattern as `unnecessary_clippy_cfg`; model the real compilation condition instead. If no stable condition exists, restructure or fix the code rather than falling back to `#[allow]`.

## No Cargo or RUSTFLAGS Escape Hatch

Do not weaken a strict project with manifest or compiler-wide permission:

```text
# Cargo.toml — forbidden by the shared strict gate
[lints.clippy]
too_many_lines = "allow"

# rustflags — also forbidden
-A dead_code
--allow=clippy::pedantic
```

Keep the lint enabled centrally and place a reasoned `#[expect]` at the source site that owns the reviewed exception.

## Keep Stale Expectations Fatal

```toml
[lints.rust]
unfulfilled_lint_expectations = "deny"
```

Do not suppress `unfulfilled_lint_expectations`; stale exceptions are supposed to fail.

## Do Not Suppress Whole Groups

Avoid broad expectations such as:

```text
#[expect(clippy::pedantic)]
#[expect(warnings)]
```

A group can gain new members as the toolchain changes and silently widen the exception. Name one concrete lint whose tradeoff was reviewed. The reusable strict gate rejects group-level handwritten suppressions.

## Do Not Suppress High-Signal Categories

Correctness, suspicious, and performance diagnostics should normally be fixed rather than waived. The reusable gate discovers current Clippy group membership and rejects handwritten expectations for members of those categories, except explicitly policy-approved measured cases such as `clippy::large_enum_variant`.

Concrete non-negotiable lints such as `unwrap_used`, `expect_used`, explicit `panic`, undocumented unsafe blocks, and lock guards held across `await` remain blocked from expectations entirely.

## Generated Code

Generated source may need unconditional lint control because the generator or target toolchain owns its shape. Keep those boundaries explicit and machine-verifiable with `package.metadata.rust-skills2.generated-lint-boundaries`; do not copy generated-code `allow` patterns into handwritten source.

Vendored code that is not a Cargo workspace member is likewise outside the handwritten source-policy surface. If vendored code becomes first-party maintained code, migrate it to the same expectation policy.

## Migration Pattern

When reviewing an existing handwritten suppression:

```text
1. Fix the code if the lint points to a real improvement.
2. Identify the one concrete lint that remains unavoidable.
3. Verify that the lint is policy-suppressible.
4. Remove Cargo/RUSTFLAGS/global allow levels.
5. Put #[expect(lint, reason = "...")] on the smallest practical source item.
6. If applicability is configuration-dependent, guard the expectation with
   the real feature/target cfg_attr.
7. Keep unfulfilled_lint_expectations fatal.
```

## Practical Guidance

- Fix before suppressing.
- Handwritten `#[allow]` is not a policy tool.
- Do not set Cargo lint levels to `allow` or pass `-A` / `--allow`.
- Never suppress a lint group.
- Never suppress correctness/suspicious/high-risk safety or panic-policy lints.
- Use one reasoned `#[expect]` for one reviewed lint.
- Keep generated-code exceptions behind explicit generated boundaries.

## See Also

- [err-expect-bugs-only](./err-expect-bugs-only.md) - Avoid panic-producing `expect()`
- [lint-deny-correctness](./lint-deny-correctness.md) - Critical lint policy
- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoid panic-style extraction
