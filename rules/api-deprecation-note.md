# api-deprecation-note

> When deliberately retaining a deprecated API, document its version and actionable migration in the attribute; do not retain obsolete APIs without an actual compatibility requirement

## Why It Matters

Deprecation is useful only when callers can understand and act on the warning.
It is not a replacement for deleting dead code in a project that need not
preserve compatibility. A bare attribute makes callers search the codebase for
the intended replacement or behavioral change.

## Bad

```rust
#[deprecated]
pub fn read_all(path: &std::path::Path) -> std::io::Result<Vec<u8>> {
    std::fs::read(path)
}
```

The compiler warns at uses of this deprecated API outside exempt contexts, not at the mere declaration, and the warning supplies no migration advice.

## Good

```rust
#[deprecated(since = "0.4.0", note = "use std::fs::read directly")]
pub fn read_all(path: &std::path::Path) -> std::io::Result<Vec<u8>> {
    std::fs::read(path)
}
```

Specify the actual deprecation version and a concrete replacement, or explain
why no direct replacement exists. If the alternative changes error handling,
ownership, or semantics, document that change too. A placeholder or empty
string technically supplies attribute metadata but does not help a caller.

## Lint Policy

Rust accepts both attribute forms on stable. On the reviewed
1.102.0-nightly, Clippy's `deprecated_attributes_without_note` checks for
the note and `deprecated_attributes_without_since` checks for a version.
Both are denied by the shared strict gate (the former explicitly and the
latter by the pedantic group in production). Handwritten source may not
suppress the explicit note requirement.

## See Also

- [api-must-use](api-must-use.md) — actionable attribute messages for discarded values
- [lint-workspace-lints](lint-workspace-lints.md) — lint severity policy
- [Rust Reference: deprecated](https://doc.rust-lang.org/reference/attributes/diagnostics.html#the-deprecated-attribute)
