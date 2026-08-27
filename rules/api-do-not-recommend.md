# api-do-not-recommend

> Use `#[diagnostic::do_not_recommend]` on legal trait impls whose appearance in diagnostics would usually mislead callers

**Rule**: `api-do-not-recommend`

## Why It Matters

Rust 1.85 stabilized `#[diagnostic::do_not_recommend]` as a hint to rustc about **diagnostic presentation**. When a trait solver encounters a broad impl whose unsatisfied bounds are implementation detail rather than useful advice, the attribute can tell rustc not to present that impl as the recommended path.

It does not change trait resolution, coherence, visibility, or program semantics. It also does not guarantee exactly what alternative wording rustc will choose.

## Good: Hide a Misleading Blanket Trait Impl

```rust
trait Serialize {}
trait WireFormat {}

#[diagnostic::do_not_recommend]
impl<T: Serialize> WireFormat for T {}

struct Packet;
impl WireFormat for Packet {}

fn require_wire<T: WireFormat>(_: T) {}

fn main() {
    require_wire(Packet);
}
```

The blanket impl still participates in trait solving exactly as before. The attribute only gives rustc permission to omit that impl when building relevant diagnostic recommendations.

## Use It for the Diagnostic, Not for Blanketness Alone

A generic or blanket impl is not automatically a bad diagnostic. Add the attribute when surfacing the impl routinely points users toward an internal detail, an impossible bound, or the wrong public abstraction.

```rust
trait InternalAdapter {}
trait PublicApi {}

#[diagnostic::do_not_recommend]
impl<T: InternalAdapter> PublicApi for T {}

struct Direct;
impl PublicApi for Direct {}

fn use_api<T: PublicApi>(_: T) {}

fn main() {
    use_api(Direct);
}
```

If the blanket impl's bounds are actually the repair users should make, hiding it would make diagnostics worse.

## The Intended Placement Is a Trait Implementation

The Rust Reference says the attribute should be placed on a **trait implementation item**. Misplacing it elsewhere is not necessarily a hard compile error, but those positions do not provide the intended trait-impl recommendation behavior.

Do not document it as a meaningful inherent-`impl` attribute.

## It Cannot Bypass Coherence or the Orphan Rules

Diagnostic attributes are processed after the language's legality rules. They cannot make an illegal impl legal.

<!-- rust-check: compile_fail; reason=demonstrates that the diagnostic hint does not bypass orphan/coherence rules -->
```rust
use std::ops::Add;

#[diagnostic::do_not_recommend]
impl<T: Add<Output = T>> Add<&T> for T {
    type Output = T;

    fn add(self, _other: &T) -> T {
        self
    }
}
```

This fails because both `Add` and the target type are foreign/uncovered in a way Rust's orphan rules reject. The diagnostic attribute has no bearing on that error.

When demonstrating `do_not_recommend`, prefer traits/types owned by the example or crate so the example is independently legal.

## It Does Not Mean “Hide This API”

The impl remains part of the program and can still affect type checking. The attribute is not:

- a visibility control;
- a sealing mechanism;
- a deprecation mechanism;
- a way to disable an impl;
- a promise that the impl will never be mentioned by any diagnostic.

Use normal language/API mechanisms for those concerns.

## Relation to Sealed Traits

A private sealing trait and `do_not_recommend` solve different problems:

- sealing controls who can implement/extend an API;
- `do_not_recommend` influences how rustc explains a failed bound involving a trait impl.

They can be used together, but one does not substitute for the other.

## Requirements and Constraints

- Stable since Rust 1.85.
- Intended for a trait `impl` item.
- Takes no arguments.
- Is a compiler diagnostic hint, not a semantic attribute.
- Does not relax orphan/coherence rules.
- Should be used only when suppressing that impl improves the likely error message.

## Practical Guidance

- Start by reading the actual compiler error users receive.
- Add `do_not_recommend` only when an impl repeatedly creates a misleading recommendation.
- Keep examples legal without the attribute; the attribute must not be used to disguise a coherence problem.
- Do not promise a particular replacement suggestion—rustc diagnostics may evolve.
- Re-test representative diagnostics when changing broad public impls.

## See Also

- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) — Canonical diagnostic-focused treatment
- [api-sealed-trait](./api-sealed-trait.md) — Sealing extension points
- [api-extension-trait](./api-extension-trait.md) — Extension trait design

## References

- [Rust Reference: diagnostic attributes](https://doc.rust-lang.org/reference/attributes/diagnostics.html#the-diagnosticdo_not_recommend-attribute)
- [Rust 1.85 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)
