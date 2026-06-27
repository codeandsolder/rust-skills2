# trait-upcasting

> Prefer implicit trait object upcasting over hand-written `as_supertrait` helpers (Rust 1.86+)

## Why It Matters

Before Rust 1.86, converting `&dyn Sub` to `&dyn Super` (where `Sub: Super`) required either manual boilerplate — every trait with supertraits needed a hand-written upcast method — or a macro. The compiler can now perform this coercion implicitly, making trait hierarchies ergonomic to work with as trait objects. This eliminates a long-standing papercut that often drove library authors to avoid trait objects in multi-level hierarchies, or to use `Any` and downcasting as a workaround.

## Bad

```rust
trait Super {
    fn super_op(&self) -> &str;
}
trait Sub: Super {
    fn sub_op(&self) -> &str;
}

// Hand-written upcast required before Rust 1.86.
trait Sub: Super {
    fn as_super(&self) -> &dyn Super;
    fn sub_op(&self) -> &str;
}

struct MyStruct;
impl Super for MyStruct {
    fn super_op(&self) -> &str { "super" }
}
impl Sub for MyStruct {
    fn as_super(&self) -> &dyn Super { self }
    fn sub_op(&self) -> &str { "sub" }
}

fn use_sub(x: &dyn Sub) {
    // Must call the explicit upcast method.
    let s: &dyn Super = x.as_super();
    println!("{}", s.super_op());
}
```

## Good

```rust
trait Super {
    fn super_op(&self) -> &str;
}
trait Sub: Super {
    fn sub_op(&self) -> &str;
}

struct MyStruct;
impl Super for MyStruct {
    fn super_op(&self) -> &str { "super" }
}
impl Sub for MyStruct {
    fn sub_op(&self) -> &str { "sub" }
}

// ----- Implicit upcasting (Rust 1.86+) -----

fn use_sub(x: &dyn Sub) {
    // Implicit coercion — no hand-written method needed.
    let s: &dyn Super = x;
    println!("{}", s.super_op());
}

// Works with Box<dyn> and Arc<dyn> too.
fn box_upcast(x: Box<dyn Sub>) -> Box<dyn Super> {
    x
}

use std::sync::Arc;
fn arc_upcast(x: Arc<dyn Sub>) -> Arc<dyn Super> {
    x
}
```

## Common Use Cases

### Enabling `dyn Any` downcasting on custom trait hierarchies

The `Any` trait is a common supertrait to enable `downcast_ref` on trait objects. Upcasting makes this trivial:

```rust
use std::any::Any;

trait Component: Any {
    fn name(&self) -> &str;
}

impl dyn Component {
    fn downcast_ref<T: Any>(&self) -> Option<&T> {
        (self as &dyn Any).downcast_ref::<T>()
    }
}
```

### Working with standard library trait hierarchies

Standard traits that form hierarchies benefit immediately:

```rust
fn eq_to_partial_eq(e: &dyn Eq) -> &dyn PartialEq {
    e  // Eq: PartialEq
}

fn ord_to_partial_ord(o: &dyn Ord) -> &dyn PartialOrd {
    o  // Ord: PartialOrd
}

fn copy_to_clone(c: &dyn Copy) -> &dyn Clone {
    c  // Copy: Clone
}
```

## Key Points

- Upcasting is an **implicit coercion**, not a conversion method — it requires no `.into()` or `.as_ref()` call.
- Works for all pointer-to-trait-object types: `&dyn`, `Box<dyn>`, `Arc<dyn>`, `*const dyn`, `*mut dyn`.
- Does **not** change object safety: a trait must already be dyn-compatible to be used as `dyn Trait` before upcasting applies.
- Not transitive for associated types — upcasting only applies to supertrait relationships, not to type parameters.
- Replaces the pattern of defining an `fn as_super(&self) -> &dyn Super` method on every subtrait.

## See Also

- [trait-object-safety](trait-object-safety.md) — keep traits dyn-compatible when you need `dyn Trait`
- [trait-dyn-vs-generic](trait-dyn-vs-generic.md) — choose between static and dynamic dispatch deliberately
- [anti-type-erasure](anti-type-erasure.md) — don't use `Box<dyn Trait>` when `impl Trait` works
