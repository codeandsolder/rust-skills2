# anti-type-erasure

> Prefer static polymorphism when one concrete type is sufficient; use `dyn Trait` deliberately when runtime type erasure and heterogeneous implementations are part of the design

## Why It Matters

Rust supports both static and dynamic polymorphism:

- generics and `impl Trait` keep a concrete type known to the compiler and use static dispatch;
- `dyn Trait` erases the concrete type behind a dyn-compatible trait and uses dynamic dispatch.

Neither is universally better. They have different semantics, API constraints, code-generation behavior, and ownership choices.

Also, **type erasure does not inherently mean `Box` or heap allocation**. Trait objects can be used behind references such as `&dyn Trait`, or owned behind `Box<dyn Trait>`, `Arc<dyn Trait>`, and other supported pointer types.

## Return `impl Trait` When One Hidden Concrete Type Is Enough

```rust
fn even_values() -> impl Iterator<Item = i32> {
    (0..10).filter(|value| value % 2 == 0)
}

fn main() {
    assert_eq!(even_values().collect::<Vec<_>>(), vec![0, 2, 4, 6, 8]);
}
```

The function chooses one hidden concrete iterator type. Callers know only the declared trait bounds, but every return path must resolve to that same concrete type.

This is excellent for closures and iterator adapters whose concrete types are awkward to name.

## Argument-Position `impl Trait` Is Caller-Chosen Static Polymorphism

```rust
trait Handler {
    fn handle(&self, value: i32) -> i32;
}

struct Double;

impl Handler for Double {
    fn handle(&self, value: i32) -> i32 {
        value * 2
    }
}

fn run(handler: impl Handler, value: i32) -> i32 {
    handler.handle(value)
}

fn main() {
    assert_eq!(run(Double, 4), 8);
}
```

Argument-position `impl Trait` is essentially an anonymous generic type parameter. The **caller** chooses the concrete implementing type for each monomorphized call.

That is different from return-position `impl Trait`, where the function chooses the hidden concrete type.

## Use `dyn Trait` for Runtime Heterogeneity

```rust
trait Handler {
    fn handle(&self, value: i32) -> i32;
}

struct Double;
struct Increment;

impl Handler for Double {
    fn handle(&self, value: i32) -> i32 {
        value * 2
    }
}

impl Handler for Increment {
    fn handle(&self, value: i32) -> i32 {
        value + 1
    }
}

fn main() {
    let handlers: Vec<Box<dyn Handler>> = vec![
        Box::new(Double),
        Box::new(Increment),
    ];

    let results: Vec<_> = handlers.iter().map(|handler| handler.handle(10)).collect();
    assert_eq!(results, vec![20, 11]);
}
```

The collection contains different concrete types selected at runtime. `Box<dyn Handler>` is appropriate because the collection needs owned heterogeneous values of one erased interface.

## A Trait Object Does Not Require Ownership or Allocation

Dynamic dispatch can operate through a borrowed trait object:

```rust
trait Describe {
    fn describe(&self) -> &'static str;
}

struct Cat;
struct Dog;

impl Describe for Cat {
    fn describe(&self) -> &'static str { "cat" }
}

impl Describe for Dog {
    fn describe(&self) -> &'static str { "dog" }
}

fn describe(value: &dyn Describe) -> &'static str {
    value.describe()
}

fn main() {
    let cat = Cat;
    let dog = Dog;
    assert_eq!(describe(&cat), "cat");
    assert_eq!(describe(&dog), "dog");
}
```

Here type erasure and dynamic dispatch happen through `&dyn Describe`; there is no `Box` involved.

## Runtime Choice of One Owned Implementation

When configuration determines the concrete implementation, an owned trait object can hide that choice:

```rust
trait Database {
    fn name(&self) -> &'static str;
}

struct MemoryDb;
struct FileDb;

impl Database for MemoryDb {
    fn name(&self) -> &'static str { "memory" }
}

impl Database for FileDb {
    fn name(&self) -> &'static str { "file" }
}

fn create_database(use_file: bool) -> Box<dyn Database> {
    if use_file {
        Box::new(FileDb)
    } else {
        Box::new(MemoryDb)
    }
}

fn main() {
    assert_eq!(create_database(false).name(), "memory");
    assert_eq!(create_database(true).name(), "file");
}
```

Return-position `impl Database` cannot express these two different concrete return types from the same function. A trait object—or a closed enum—is the natural choice.

## Closed Runtime Sets Often Fit an Enum

If all implementations are known and controlled by the crate, an enum can preserve a concrete sized representation:

```rust
trait ShapeArea {
    fn area(&self) -> f64;
}

enum Shape {
    Circle { radius: f64 },
    Rectangle { width: f64, height: f64 },
}

impl ShapeArea for Shape {
    fn area(&self) -> f64 {
        match self {
            Shape::Circle { radius } => std::f64::consts::PI * radius * radius,
            Shape::Rectangle { width, height } => width * height,
        }
    }
}

fn main() {
    let shape = Shape::Rectangle { width: 3.0, height: 4.0 };
    assert_eq!(shape.area(), 12.0);
}
```

An enum is attractive when exhaustiveness and a closed set matter. A trait object is attractive when implementations form an open set or runtime erasure is part of the API.

## Return-Position `impl Trait` in Traits Is Stable

Modern Rust permits return-position `impl Trait` in trait methods; it is desugared to an anonymous associated type:

```rust
trait Numbers {
    fn values(&self) -> impl Iterator<Item = i32> + '_;
}

struct Pair(i32, i32);

impl Numbers for Pair {
    fn values(&self) -> impl Iterator<Item = i32> + '_ {
        [self.0, self.1].into_iter()
    }
}

fn sum(numbers: &impl Numbers) -> i32 {
    numbers.values().sum()
}

fn main() {
    assert_eq!(sum(&Pair(2, 3)), 5);
}
```

The old claim that `impl Trait` “cannot be used in trait definitions” has been obsolete since return-position `impl Trait` in traits stabilized in Rust 1.75.

However, a trait method with an opaque return type (`impl Trait`) is not dispatchable through a trait object, so such a trait is not dyn-compatible unless that method is explicitly excluded from trait-object dispatch (for example with an appropriate `Self: Sized` design). Static trait use and dyn compatibility are separate concerns.

## Static and Dynamic Dispatch Have Different Performance Shapes

Static dispatch can enable inlining and avoids a vtable call, but monomorphization can increase generated code size and compile time. Dynamic dispatch adds an indirect call and generally limits inlining at that call boundary, while potentially reducing duplicated code.

Do not turn those tendencies into universal tables such as “generics = larger binary” or “dyn = smaller/faster compile.” Optimizers, call frequency, implementation size, LTO, and workload all matter.

Benchmark or inspect binary/code size when the distinction is material.

## `Box<dyn Trait>` Adds Allocation Because of `Box`, Not Because of `dyn`

An owned `Box<dyn Trait>` normally allocates the concrete value on the heap. `&dyn Trait` does not. `Arc<dyn Trait>` uses reference-counted ownership. Pick the pointer/ownership model separately from the dispatch model.

This distinction prevents the common mistake of equating “trait object” with “heap allocation.”

## Practical Guidance

- Return `impl Trait` when the callee can choose one hidden concrete type.
- Use argument-position `impl Trait`/generics when callers choose concrete types and static dispatch is appropriate.
- Use `dyn Trait` when runtime heterogeneity or deliberate type erasure is required.
- Choose `&dyn`, `Box<dyn>`, `Arc<dyn>`, etc. from ownership/lifetime needs; `dyn` itself does not mandate heap allocation.
- Prefer an enum for a closed, known implementation set when exhaustiveness is useful.
- Remember RPITIT is stable, but opaque-return trait methods generally prevent dyn compatibility.
- Measure code size/runtime/compile-time effects instead of relying on blanket “zero-cost” or “smaller binary” claims.

## See Also

- [anti-over-abstraction](./anti-over-abstraction.md) - Choosing abstraction boundaries
- [async-fn-in-trait](./async-fn-in-trait.md) - Async/RPITIT trait contracts and dyn compatibility
- [type-generic-bounds](./type-generic-bounds.md) - Generic constraints
- [mem-box-large-variant](./mem-box-large-variant.md) - Indirection and layout trade-offs
