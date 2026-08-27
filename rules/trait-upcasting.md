# trait-upcasting

> Use trait-object upcasting for dyn-compatible supertrait relationships (Rust 1.86+)

## Why It Matters

Rust 1.86 stabilized trait-object upcasting coercions: when `Sub: Super`, a `dyn Sub` trait object can coerce to `dyn Super` as long as the relevant traits are dyn-compatible.

This removes many hand-written `as_supertrait` helpers. It does **not** make non-dyn-compatible traits usable as trait objects, and it does not change ordinary generic trait bounds.

## Good: Reference Upcasting

```rust
trait Named {
    fn name(&self) -> &str;
}

trait Widget: Named {
    fn width(&self) -> u32;
}

struct Button;

impl Named for Button {
    fn name(&self) -> &str {
        "button"
    }
}

impl Widget for Button {
    fn width(&self) -> u32 {
        80
    }
}

fn named(value: &dyn Widget) -> &dyn Named {
    value
}

fn main() {
    let button = Button;
    let widget: &dyn Widget = &button;
    assert_eq!(named(widget).name(), "button");
    assert_eq!(widget.width(), 80);
}
```

The conversion is a coercion; there is no `.into()` method or runtime downcast involved.

## Owning Trait Objects Can Upcast Too

Pointer-like owners that support the corresponding unsizing coercion can carry the trait-object upcast through the pointer.

```rust
trait Base {
    fn value(&self) -> u32;
}

trait Derived: Base {}

struct Item(u32);

impl Base for Item {
    fn value(&self) -> u32 {
        self.0
    }
}
impl Derived for Item {}

fn upcast(value: Box<dyn Derived>) -> Box<dyn Base> {
    value
}

fn main() {
    let value: Box<dyn Derived> = Box::new(Item(7));
    assert_eq!(upcast(value).value(), 7);
}
```

The same general coercion machinery is used by standard smart pointers such as `Arc` where the pointer type supports unsizing.

## `Any` Supertraits Become Easier to Use

```rust
use std::any::Any;

trait Component: Any {
    fn kind(&self) -> &'static str;
}

impl dyn Component {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

struct Counter;
impl Component for Counter {
    fn kind(&self) -> &'static str {
        "counter"
    }
}

fn main() {
    let component: &dyn Component = &Counter;
    assert!(component.as_any().is::<Counter>());
}
```

This is an upcast from `dyn Component` to its `Any` supertrait, followed by `Any`'s normal downcasting API.

## Standard-Library Supertraits Still Need Dyn Compatibility

Do not infer that every familiar trait hierarchy is a usable trait-object hierarchy. A trait must already satisfy Rust's dyn-compatibility rules before `dyn Trait` exists.

For example, examples such as these are invalid:

<!-- rust-check: compile_fail; reason=demonstrates that trait upcasting does not make non-dyn-compatible standard traits into trait objects -->
```rust
fn bad(_: &dyn Eq) {}
```

`Eq`, `Ord`, and `Copy` are not suitable examples for trait-object upcasting because their trait definitions are not dyn-compatible in the required way. Stabilizing upcasting did not change that.

A dyn-compatible standard hierarchy does work. `std::error::Error` has dyn-compatible `Debug` and `Display` supertraits:

```rust
use std::fmt::Display;

fn as_display(error: &dyn std::error::Error) -> &dyn Display {
    error
}
```

## Upcasting Is Not Downcasting

Upcasting forgets capabilities: `dyn Derived -> dyn Base`. It is guaranteed by the declared supertrait relationship.

Going the other direction (`dyn Base -> dyn Derived`) is a downcast and cannot be inferred from the base trait alone. Use a deliberate mechanism such as `Any`, an enum, or an application-specific registry when you actually need runtime type recovery.

## Dyn Compatibility Still Applies

A trait used as `dyn Trait` must satisfy the language's dyn-compatibility rules. Among other restrictions, all of its supertraits must themselves be dyn-compatible, and the trait cannot require `Self: Sized` as a supertrait.

```rust
trait Base {
    fn id(&self) -> u32;
}

trait NotDyn: Base + Sized {
    fn consume(self);
}

// `dyn NotDyn` is invalid because the trait requires `Sized`.
```

Upcasting is useful only after the trait-object design is valid in the first place.

## Migration Guidance

If a pre-1.86 API has an `as_super(&self) -> &dyn Super` method solely to work around the old language limitation, consider removing or deprecating that helper when your MSRV is 1.86 or newer.

Keep a named helper if it has additional semantics, is part of a compatibility promise, or is clearer at a public API boundary. Language support removes the technical necessity, not every possible reason for an explicit method.

## See Also

- [trait-object-safety](./trait-object-safety.md) — dyn-compatible trait design
- [trait-dyn-vs-generic](./trait-dyn-vs-generic.md) — dynamic versus static dispatch
- [anti-type-erasure](./anti-type-erasure.md) — avoid unnecessary type erasure
