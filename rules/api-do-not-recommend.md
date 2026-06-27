# api-do-not-recommend

> Use `#[diagnostic::do_not_recommend]` (Rust 1.85.0) to hide blanket impls from compiler diagnostics

**Rule**: `api-do-not-recommend`

## Why It Matters

Blanket impls are powerful but cause misleading compiler suggestions. When a user writes code that doesn't quite satisfy a trait bound, the compiler may suggest implementing the trait for their type, even when the blanket impl is the wrong path. `#[diagnostic::do_not_recommend]` hides the implementation from suggestion lists, steering users toward the correct solution.

## Bad

```rust
// Blanket impl that confuses compiler diagnostics
pub trait MyTrait {
    fn process(&self);
}

// Internal sealed trait — users should NOT implement this directly
pub trait InternalProcess {
    fn internal_process(&self);
}

// Blanket impl: anyone with InternalProcess gets MyTrait
impl<T: InternalProcess> MyTrait for T {
    fn process(&self) {
        self.internal_process();
    }
}

// User code that fails to compile:
fn do_work(x: &impl MyTrait) { }

struct MyType;

do_work(&MyType);  // Error: MyTrait not implemented
// Compiler suggests: "consider implementing MyTrait for MyType"
// But that's misleading — user should implement InternalProcess
```

## Good

```rust
pub trait MyTrait {
    fn process(&self);
}

pub trait InternalProcess {
    fn internal_process(&self);
}

// Hide the blanket impl from compiler diagnostics
#[diagnostic::do_not_recommend]
impl<T: InternalProcess> MyTrait for T {
    fn process(&self) {
        self.internal_process();
    }
}

struct MyType;

// Now the compiler won't suggest implementing MyTrait directly
// Instead it will suggest implementing InternalProcess
impl InternalProcess for MyType {
    fn internal_process(&self) {
        // ...
    }
}
```

## Common Use Cases

```rust
// 1. Sealed trait blanket impls
pub trait Format: private::Sealed {
    fn format(&self) -> String;
}

#[diagnostic::do_not_recommend]
impl<T: private::Sealed + Display> Format for T {
    fn format(&self) -> String {
        self.to_string()
    }
}


// 2. Extension trait blanket impls
pub trait ParseExt: Sized {
    fn parse_to<T: FromStr>(&self) -> Result<T, T::Err>;
}

#[diagnostic::do_not_recommend]
impl<S: AsRef<str>> ParseExt for S {
    fn parse_to<T: FromStr>(&self) -> Result<T, T::Err> {
        self.as_ref().parse()
    }
}


// 3. Operator overloading helpers
use std::ops::Add;

#[diagnostic::do_not_recommend]
impl<T: Add<Output = T>> Add<&T> for T {
    type Output = T;
    fn add(self, other: &T) -> T {
        self + *other
    }
}
```

## Requirements

- Rust 1.85.0 or later (stable since February 2025)
- Applies to `impl` blocks only
- Does not affect trait resolution — only diagnostic output
- Can be applied to both inherent impls and trait impls

## See Also

- [api-sealed-trait](./api-sealed-trait.md) — Sealed traits to prevent external implementations
- [api-extension-trait](./api-extension-trait.md) — Add methods to external types
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) — Hide blanket impls from suggestions

## References

- [Rust 1.85.0 release notes](https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/)
- [api-sealed-trait](./api-sealed-trait.md) — Sealed traits (common companion)
- [api-extension-trait](./api-extension-trait.md) — Extension traits
