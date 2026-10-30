# lint-pedantic-selective

**Rule**: `lint-pedantic-selective`

> Enable `clippy::pedantic` as a baseline, review its findings individually, and use narrow reasoned `#[expect]` exceptions instead of disabling lints with `allow`

## Why It Matters

The `clippy::pedantic` group contains many useful diagnostics plus some intentionally opinionated heuristics. Turning the whole group off loses signal; permanently allowing selected members in `Cargo.toml` also makes exceptions invisible at the source sites they affect.

The strict project policy keeps the group enabled and treats exceptions as local, reviewable source annotations. A stale `#[expect]` fails through `unfulfilled_lint_expectations`, so exceptions disappear when the code or lint evolves.

## Priority System (Rust 1.74+)

When enabling a whole group, use a negative priority so individually stricter lint levels can override it:

```toml
[lints.clippy]
pedantic = { level = "warn", priority = -1 }

# Promote particularly useful members.
doc_markdown = "deny"
unused_self = "deny"
wildcard_imports = "deny"
```

Do not use the priority system to set noisy members to `allow` under the strict policy. Keep them enabled and handle genuine exceptions at the smallest source site with a reasoned expectation.

## Bad

```toml
[lints.clippy]
pedantic = { level = "warn", priority = -1 }

# Permanent broad holes: forbidden by the strict gate.
missing_errors_doc = "allow"
too_many_lines = "allow"
module_name_repetitions = "allow"
```

Likewise, do not use crate- or module-wide `#[allow(clippy::pedantic)]`.

## Good

```toml
[lints.clippy]
pedantic = { level = "warn", priority = -1 }
```

Then review a concrete diagnostic. Fix it when the suggested design is better; otherwise keep the exception next to the code:

```rust
#[expect(
    clippy::too_many_lines,
    reason = "parser state machine mirrors the protocol grammar and is easier to audit as one transition table"
)]
fn parse_frame() {
    // ...
}
```

## High-Value Pedantic Lints

| Lint | Why It Helps |
|------|--------------|
| `doc_markdown` | Catch unmarked code identifiers in docs |
| `match_wildcard_for_single_variants` | Keep variant handling explicit |
| `semicolon_if_nothing_returned` | Make statement intent consistent |
| `string_add_assign` | Prefer the direct append operation |
| `unnested_or_patterns` | Simplify match patterns |
| `unused_self` | Catch methods that do not use their receiver |
| `used_underscore_binding` | Catch bindings whose name implies “unused” but are used |
| `wildcard_imports` | Avoid hidden namespace growth |

## Commonly Noisy Heuristics

These are not a reason to disable the lints globally. They are frequent candidates for either a code improvement or a narrow expectation after review:

| Lint | Typical tradeoff to review |
|------|----------------------------|
| `missing_errors_doc` | Internal/public API documentation boundary |
| `missing_panics_doc` | Whether panic behavior is actually part of the contract |
| `module_name_repetitions` | Public naming clarity versus repetition |
| `must_use_candidate` | Whether ignoring the return value is genuinely suspicious |
| `too_many_lines` | Cohesion versus arbitrary function-size threshold |
| `struct_excessive_bools` | Explicit independent flags versus a richer state type |
| `similar_names` | Domain terminology versus accidental confusion |

## Proc-Macro Expansions

New pedantic lints can surface diagnostics whose implementation originates in a third-party derive or proc macro. First determine whether the warning points to handwritten code or generated expansion.

If a source item invoking the macro is the narrowest place that can own a suppressible diagnostic, attach one reasoned `#[expect]` there. If the diagnostic is entirely inside generated source, use an explicit generated-lint boundary rather than weakening handwritten policy.

Do not disable `clippy::pedantic` for the crate or workspace just because one macro expansion is noisy.

## Configuration-Dependent Cases

If a lint is genuinely present only under one feature or target, put the expectation behind that **real** condition:

```rust
#[cfg_attr(
    feature = "legacy-schema",
    expect(
        clippy::struct_field_names,
        reason = "legacy-schema exposes externally fixed field names"
    )
)]
pub struct TupleFields {
    pub tuple_id: u64,
    pub tuple_source: u64,
}
```

Do not use `cfg(clippy)` as a generic escape hatch and do not fall back to `#[allow]`.

## Team Policy

1. Enable `pedantic` as a baseline.
2. Run Clippy across the configurations CI claims to support.
3. Fix diagnostics that improve the code.
4. For a genuine heuristic tradeoff, use one reasoned `#[expect]` at the narrowest source site.
5. Keep `unfulfilled_lint_expectations` fatal.
6. Never use Cargo lint level `allow`, handwritten `#[allow]`, or `-A` / `--allow` to silence pedantic findings.

## See Also

- [lint-warn-style](./lint-warn-style.md) - Style warnings
- [lint-warn-complexity](./lint-warn-complexity.md) - Complexity warnings
- [lint-deny-correctness](./lint-deny-correctness.md) - Correctness lints
- [err-expect-not-allow](./err-expect-not-allow.md) - Exception policy
