# err-expect-not-allow

> Prefer `#[expect(...)]` over `#[allow(...)]` for suppressing lint warnings

## Why It Matters

Since Rust 1.80, `#[expect(clippy::lint_name, reason = "...")]` is preferred over `#[allow(clippy::lint_name)]`. The key difference: an unfulfilled `expect` fires a warning when the suppression is no longer needed, alerting you to remove stale annotations. `#[allow]` silently accumulates dead code.

## Bad

```rust
// Dead allow — never cleans itself up
#[allow(clippy::unwrap_used)]
fn from_env() -> String {
    std::env::var("HOME").unwrap()
}

// After the unwrap is removed, this allow silently lingers
fn from_env() -> String {
    std::env::var("HOME").unwrap_or_default()
}
```

## Good

```rust
// expect — warns when the lint no longer fires
#[expect(clippy::unwrap_used, reason = "env::var always succeeds when configured")]
fn from_env() -> String {
    std::env::var("HOME").unwrap()
}

// After the unwrap is removed, clippy warns: "expected lint clippy::unwrap_used has been fulfilled"
// Tells you to delete the annotation
```

## Lint Categories Supported

```rust
// Works with any lint, but especially useful for:
#[expect(clippy::unwrap_used, reason = "...")]
#[expect(clippy::expect_used, reason = "...")]
#[expect(clippy::panic, reason = "...")]
#[expect(clippy::missing_errors_doc, reason = "internal function")]
#[expect(clippy::missing_panics_doc, reason = "controlled panic on invariant")]
```

## What Happens When an Expect is Stale

```rust
// 1. Start with this — expect is active because unwrap_used fires
#[expect(clippy::unwrap_used, reason = "validated input")]
fn process(id: u64) -> u64 {
    id.checked_add(1).unwrap()
}

// 2. Code changes — unwrap removed, unwrap_used no longer fires
fn process(id: u64) -> u64 {
    id.saturating_add(1)
}

// 3. Clippy now warns:
// warning: expected lint `clippy::unwrap_used` has been fulfilled
// help: remove this `#[expect(...)]` attribute
```

## Migration from #[allow]

```rust
// Before (Rust < 1.80)
#[allow(clippy::unwrap_used)]
fn helper() -> i32 {
    tricky_computation().unwrap()
}

// After (Rust 1.80+)
#[expect(clippy::unwrap_used, reason = "tricky_computation always returns Some")]
fn helper() -> i32 {
    tricky_computation().unwrap()
}
```

## Use in CI

Enable the `fulfill_expectations` lint to turn unfulfilled expectations into errors:

```toml
# Cargo.toml
[lints.rust]
fulfill_expectations = "deny"
```

This ensures stale `#[expect]` annotations are never accidentally left in the codebase.

## When #[allow] Is Still Acceptable

- In `cfg(test)` modules where the lint condition is genuinely conditional
- For lints that can't be expressed with `#[expect]` (e.g., conditional compilation gates)
- As a temporary measure, always cleaned up before merge

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) — Avoiding unwrap in production
- [err-expect-bugs-only](./err-expect-bugs-only.md) — When expect() is appropriate
- [lint-deny-correctness](./lint-deny-correctness.md) — Compiler lint configuration
