# err-diagnostic-do-not-recommend

> Use `#[diagnostic::do_not_recommend]` on trait impls whose appearance in diagnostics would mislead users

## Why It Matters

Rust 1.85 added `#[diagnostic::do_not_recommend]` as a library-author hint for compiler diagnostics. It tells rustc not to present the annotated **trait implementation** as a suggested path when explaining an unsatisfied trait bound.

This is useful for broad blanket impls, internal adapter impls, or impls whose bounds are usually not something the caller should try to satisfy. It is not specific to errors or `From`, and it does not change trait resolution, coherence, or program semantics.

## Bad

```rust
trait Serialize {}
trait WireFormat {}

// Suppose this is an internal convenience blanket impl. If a user's type does
// not implement WireFormat, diagnostics may point at the Serialize bound and
// make implementing Serialize look like the intended fix.
impl<T: Serialize> WireFormat for T {}

struct Packet;
impl WireFormat for Packet {}

fn main() {}
```

The blanket impl may be perfectly valid, but exposing it in a diagnostic can send users toward an implementation detail rather than the public trait they actually need.

## Good

```rust
trait Serialize {}
trait WireFormat {}

#[diagnostic::do_not_recommend]
impl<T: Serialize> WireFormat for T {}

// Direct implementations remain ordinary trait implementations.
struct Packet;
impl WireFormat for Packet {}

fn require_wire<T: WireFormat>(_: T) {}

fn main() {
    require_wire(Packet);
}
```

The attribute only changes how rustc may explain relevant failures. The blanket impl still exists and participates in trait solving exactly as before.

## What the Attribute Actually Does

The Rust Reference describes this as a hint to omit the annotated trait impl from diagnostic recommendations. The compiler is not required to use diagnostic hints in every situation.

Use it when all of the following are true:

- the item is a trait `impl`;
- the impl is technically relevant to trait solving;
- surfacing that impl commonly suggests the wrong repair, exposes an internal detail, or points at bounds callers cannot reasonably satisfy.

Do not add it merely because an impl is generic. Useful diagnostics are part of an API, and hiding a genuinely actionable impl makes errors worse.

## It Is Not an Error-Conversion Feature

This attribute is often useful on blanket trait impls, but there is nothing special about `From` or error types. In particular, do not copy examples such as:

<!-- rust-check: compile_fail; reason=demonstrates that the diagnostic attribute does not bypass orphan/coherence rules -->
```rust
// Illegal regardless of the diagnostic attribute: both the trait and target
// type are foreign, so this violates Rust's orphan/coherence rules.
#[diagnostic::do_not_recommend]
impl<T: std::error::Error + 'static> From<T> for Box<dyn std::error::Error> {
    fn from(err: T) -> Self {
        Box::new(err)
    }
}
```

If you own the trait or the target type and have a legal impl whose diagnostic is misleading, the attribute may be appropriate. It never makes an otherwise-illegal impl legal.

## Placement

`#[diagnostic::do_not_recommend]` belongs on a trait implementation and takes no arguments. Rustc warns about misplaced or malformed uses.

```rust
trait InternalAdapter {}
trait PublicTrait {}

#[diagnostic::do_not_recommend]
impl<T: InternalAdapter> PublicTrait for T {}

fn main() {}
```

## See Also

- [err-from-impl](./err-from-impl.md) — `From` implementations for error propagation
- [err-custom-type](./err-custom-type.md) — Custom error types
- [err-question-mark](./err-question-mark.md) — The `?` operator
