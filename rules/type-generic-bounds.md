# type-generic-bounds

> Add trait bounds only where needed

**Rule**: `type-generic-bounds`

## Why It Matters

Trait bounds constrain what types can be used with generic code. Adding unnecessary bounds limits flexibility. Adding bounds in the right place (impl vs function vs where clause) affects usability and readability. Well-placed bounds keep APIs flexible while ensuring type safety.

## Bad

```rust
// Bounds on struct definition — limits all uses
struct Container<T: Clone + Debug> {  // Even storage requires Clone?
    items: Vec<T>,
}

// Inline bounds make signature hard to read
fn process<T: Clone + Debug + Send + Sync + 'static, E: Error + Send + Clone>(
    value: T,
) -> Result<T, E> { ... }

// Redundant bounds
fn print_twice<T: Clone + Debug>(value: T)
where
    T: Clone,  // Already specified above
{ ... }
```

## Good

```rust
// No bounds on struct — store anything
struct Container<T> {
    items: Vec<T>,
}

// Bounds only on impls that need them
impl<T: Clone> Container<T> {
    fn duplicate(&self) -> Self {
        Container { items: self.items.clone() }
    }
}

impl<T: Debug> Container<T> {
    fn debug_print(&self) {
        println!("{:?}", self.items);
    }
}

// Where clause for readability
fn process<T, E>(value: T) -> Result<T, E>
where
    T: Clone + Debug + Send + Sync + 'static,
    E: Error + Send + Clone,
{ ... }
```

## Bound Placement

```rust
// On struct: affects all uses of the type
struct MustBeClone<T: Clone> { data: T }  // Rarely needed

// On impl: affects specific functionality
impl<T: Clone> Container<T> { ... }  // Common pattern

// On function: affects that function only
fn requires_send<T: Send>(value: T) { ... }

// Recommendation: start with no bounds, add as needed
```

## Where Clause Benefits

```rust
// Inline: hard to read
fn complex<T: Clone + Debug + Send, U: AsRef<str> + Into<String>>(t: T, u: U) {}

// Where clause: clear and scannable
fn complex<T, U>(t: T, u: U)
where
    T: Clone + Debug + Send,
    U: AsRef<str> + Into<String>,
{ }

// Essential for complex bounds
fn foo<T, U>(t: T, u: U)
where
    T: Iterator<Item = U>,
    U: Clone + Into<String>,
    Vec<U>: Debug,  // Bounds on expressions
{ }
```

## Implied Bounds

```rust
// Supertrait bounds are implied
trait Foo: Clone + Debug {}

fn process<T: Foo>(value: T) {
    // T: Clone and T: Debug are implied by T: Foo
    let cloned = value.clone();
    println!("{:?}", cloned);
}

// Associated type bounds
fn process<I>(iter: I)
where
    I: Iterator,
    I::Item: Clone,  // Bound on associated type
{ }
```

## Precise Capturing with `use<...>` (Rust 1.87+)

In Edition 2024, `impl Trait` in return position has stricter capturing rules. Use `use<...>` to precisely specify which generic parameters are captured:

```rust
// Without precise capturing: compiler may infer too many captures
fn make_debug<T: Debug>(t: T) -> impl Debug { t }  // Captures T

// With precise capturing (Rust 1.87+): explicit about what's captured
fn make_debug<T: Debug>(t: T) -> impl Debug + use<T> { t }

// Trait definitions with precise captures
trait Factory {
    // The precise captures in the return type are explicit
    fn build(&self) -> impl Debug + use<'_>;
}

// Prevents accidentally capturing unrelated type parameters
fn with_static<T: Debug>(t: T) -> impl Debug + use<T> {
    // Only T is captured — no unintended lifetime captures
    t
}
```

## Const Generic `_` Inference (Rust 1.89+)

Let the compiler infer const generic values where the context makes them obvious:

```rust
// Before: must specify the const generic explicitly
fn identity<const N: usize>(arr: [u8; N]) -> [u8; N] { arr }
let result = identity::<3>([1, 2, 3]);

// After (Rust 1.89+): let the compiler infer N from the input
fn identity<const N: usize>(arr: [u8; N]) -> [u8; N] { arr }
let result = identity([1, 2, 3]);  // N inferred as 3

// Use _ when the value doesn't matter for the API
struct Buffer<const N: usize>;
fn process(buf: Buffer<512>) {}
// _ is inferred at call site
```

## `cfg_select!` for Bound-Aware Conditional Compilation (Rust 1.95+)

```rust
use core::cfg_select;

// Platform-dependent bounds without cfg attributes everywhere
trait PlatformTrait {
    fn platform_op(&self);
}

// cfg_select! chooses the bound at compile time
fn platform_fn()
where
    // Platform-dependent bounds evaluated at compile time
    Self: cfg_select! {
        target_os = "linux" => PlatformTrait,
        target_os = "windows" => PlatformTrait,
        _ => Sized,  // Fallback — no extra bound
    },
{ ... }
```

## Conditional Trait Implementation

```rust
struct Wrapper<T>(T);

// Implement Clone only when T: Clone
impl<T: Clone> Clone for Wrapper<T> {
    fn clone(&self) -> Self {
        Wrapper(self.0.clone())
    }
}

// Implement Debug only when T: Debug
impl<T: Debug> Debug for Wrapper<T> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Wrapper").field(&self.0).finish()
    }
}

// Wrapper<i32> is Clone + Debug
// Wrapper<NonCloneable> is neither
```

## See Also

- [Rust Reference: Trait Bounds](https://doc.rust-lang.org/reference/trait-bounds.html)
- [Rust 1.87: Precise capturing](https://blog.rust-lang.org/2025/05/15/Rust-1.87.0/)
- [Rust 1.89: Const generic inference](https://blog.rust-lang.org/2025/08/07/Rust-1.89.0/)
- [api-impl-into](./api-impl-into.md) — Using `Into` bounds
- [api-impl-asref](./api-impl-asref.md) — Using `AsRef` bounds
- [name-type-param-single](./name-type-param-single.md) — Type parameter naming
