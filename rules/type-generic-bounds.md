# type-generic-bounds

> Put each trait bound on the API surface that actually requires it

**Rule**: `type-generic-bounds`

## Why It Matters

A trait bound is part of an API's contract. Putting a bound on a generic type definition constrains every use of that type; putting it on one `impl` or method constrains only that functionality. Unnecessary bounds reject otherwise-valid callers and can make downstream trait implementations harder to compose.

Start from the operations and invariants the API needs, then place the corresponding bounds at the narrowest useful level. A bound on the type itself is appropriate when the type's definition or invariant genuinely requires it; it is not merely a style preference to avoid all type-level bounds.

## Bad

```rust
use std::fmt::Debug;

// Storage itself does not require Clone or Debug, but every Container<T>
// is forced to satisfy both bounds.
struct Container<T: Clone + Debug> {
    items: Vec<T>,
}

fn main() {}
```

## Good

```rust
use std::fmt::Debug;

struct Container<T> {
    items: Vec<T>,
}

impl<T> Container<T> {
    fn new(items: Vec<T>) -> Self {
        Self { items }
    }

    fn len(&self) -> usize {
        self.items.len()
    }
}

impl<T: Clone> Container<T> {
    fn duplicate(&self) -> Self {
        Self { items: self.items.clone() }
    }
}

impl<T: Debug> Container<T> {
    fn debug_print(&self) {
        println!("{:?}", self.items);
    }
}

fn main() {
    let values = Container::new(vec![1, 2, 3]);
    assert_eq!(values.len(), 3);
    let _copy = values.duplicate();
    values.debug_print();
}
```

`Container<T>` can store any `T`; only operations that clone or format elements require those capabilities.

## Type-Level Bounds Are Sometimes Real Requirements

A definition can itself require a bound because one of its fields or invariants requires the associated type relationship:

```rust
struct IterState<I: Iterator> {
    iter: I,
    current: Option<I::Item>,
}

fn main() {
    let state = IterState {
        iter: [1, 2].into_iter(),
        current: Some(1),
    };
    assert_eq!(state.current, Some(1));
}
```

Here `I::Item` cannot even be named without knowing that `I: Iterator`, so the bound belongs on the type.

## Method and `impl` Bounds

Choose between an `impl`-level bound and a method-level bound based on how much functionality shares the requirement:

```rust
struct Wrapper<T>(T);

impl<T> Wrapper<T> {
    fn into_inner(self) -> T {
        self.0
    }

    fn cloned_inner(&self) -> T
    where
        T: Clone,
    {
        self.0.clone()
    }
}

fn main() {
    let value = Wrapper(String::from("hello"));
    assert_eq!(value.cloned_inner(), "hello");
}
```

If several related methods all require the same bound, a separate `impl<T: Bound>` block is often clearer. If only one method needs it, a method `where` clause avoids constraining unrelated methods.

## Readability: Inline vs `where`

Inline bounds are concise for short signatures. `where` clauses are useful when several parameters, associated types, or higher-order relationships are involved.

```rust
use std::fmt::Debug;

fn summarize<I>(iter: I) -> usize
where
    I: IntoIterator,
    I::Item: Debug,
{
    iter.into_iter().inspect(|item| println!("{item:?}")).count()
}

fn main() {
    assert_eq!(summarize([1, 2, 3]), 3);
}
```

Do not duplicate the same bound both inline and in a `where` clause unless a macro or generated API has a specific reason to do so.

## Associated Type Bounds (Rust 1.79+)

Rust 1.79 stabilized bounds in associated-type position. This:

```rust
fn copy_items<I>(iter: I) -> Vec<I::Item>
where
    I: Iterator<Item: Copy>,
{
    iter.collect()
}

fn main() {
    assert_eq!(copy_items([1, 2, 3].into_iter()), vec![1, 2, 3]);
}
```

is equivalent, for this use, to separating the constraints:

```rust
fn copy_items<I>(iter: I) -> Vec<I::Item>
where
    I: Iterator,
    I::Item: Copy,
{
    iter.collect()
}

fn main() {
    let _ = copy_items([1, 2, 3].into_iter());
}
```

Use the inline associated-type form when it makes the relationship easier to scan; use separate `where` predicates when the associated type participates in several constraints.

## Supertraits and Implied Trait Bounds

If a trait declares a supertrait, users of that trait may rely on the supertrait requirement without repeating it:

```rust
use std::fmt::Debug;

trait Record: Clone + Debug {}

#[derive(Clone, Debug)]
struct Entry;
impl Record for Entry {}

fn duplicate_and_print<T: Record>(value: T) {
    let cloned = value.clone();
    println!("{cloned:?}");
}

fn main() {
    duplicate_and_print(Entry);
}
```

Do not confuse these declared trait relationships with arbitrary bounds from a caller: Rust only implies specific categories of bounds, such as supertraits and certain lifetime/well-formedness requirements.

## Precise `impl Trait` Captures (Rust 1.82+)

Rust 1.82 stabilized `use<...>` precise capture syntax for supported return-position `impl Trait` uses. Edition 2024 **broadens** the default capture rules so in-scope lifetime parameters are automatically captured; `use<...>` lets an API make a narrower capture set explicit when needed.

```rust
use std::fmt::Debug;

fn as_debug<T: Debug>(value: T) -> impl Debug + use<T> {
    value
}

fn borrow<'a, T>(value: &'a T) -> impl Copy + use<'a, T> {
    value
}

fn main() {
    let value = 5;
    let _ = as_debug(value);
    let _ = borrow(&value);
}
```

This is a capture rule for an opaque return type, not another reason to add semantic trait bounds to `T`. In current stable Rust, precise capture syntax also has placement/rule details that should be checked in the Reference when designing a public opaque-return API.

## Conditional Trait Implementations

Trait implementations themselves are a natural place for capability bounds:

```rust
use std::fmt::{self, Debug, Formatter};

struct Wrapper<T>(T);

impl<T: Clone> Clone for Wrapper<T> {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl<T: Debug> Debug for Wrapper<T> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Wrapper").field(&self.0).finish()
    }
}

fn main() {
    let value = Wrapper(7);
    println!("{:?}", value.clone());
}
```

`Wrapper<T>` exists for any `T`, while `Wrapper<T>: Clone` or `Debug` only when the wrapped value supports the corresponding operation.

## Keep Unrelated Language Features Out of Bound Advice

Ordinary const-generic inference has existed independently of newer `_` generic-argument syntax, and `cfg_select!` selects code based on configuration rather than manufacturing a trait bound inside a `where` clause. Do not use either as generic-bound guidance unless the actual API specifically requires those features.

## See Also

- [Rust Reference: Trait Bounds](https://doc.rust-lang.org/reference/trait-bounds.html)
- [Rust 1.79: Associated item bounds](https://blog.rust-lang.org/2024/06/13/Rust-1.79.0/)
- [Rust 1.82: Precise capturing](https://blog.rust-lang.org/2024/10/17/Rust-1.82.0/)
- [api-impl-into](./api-impl-into.md) — Using `Into` bounds
- [api-impl-asref](./api-impl-asref.md) — Using `AsRef` bounds
- [name-type-param-single](./name-type-param-single.md) — Type parameter naming
