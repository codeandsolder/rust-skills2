# type-never-diverge

> Use the never type `!` for functions that never return

**Rule**: `type-never-diverge`

## Why It Matters

The never type `!` indicates a function will never return normally — it either loops forever, panics, or exits the process. This helps the compiler understand control flow and enables `!` to coerce to any type, making it useful in match arms and expressions. Since Rust 1.92, the never-type fallback lints (`unused_must_use`, `dead_code` on `!`-typed expressions) are deny-by-default, making the type system more consistent.

## Bad

```rust
// Return type doesn't indicate non-returning
fn infinite_loop() {
    loop { process_events(); }
    // Implicit () return type, but never returns
}

// Using Option when it always panics
fn unreachable_code() -> Option<()> {
    panic!("This should never be called");
}
```

## Good

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
// ! indicates function never returns
fn infinite_loop() -> ! {
    loop { process_events(); }
}

fn abort_with_error(msg: &str) -> ! {
    eprintln!("Fatal error: {}", msg);
    std::process::exit(1);
}

fn panic_handler() -> ! {
    panic!("Unexpected state");
}
```

## Coercion to Any Type

```rust
// ! coerces to any type
fn get_value(opt: Option<i32>) -> i32 {
    match opt {
        Some(v) => v,
        None => panic!("No value"),  // panic! returns !, coerces to i32
    }
}

// Useful in Result handling
fn must_get_config() -> Config {
    match load_config() {
        Ok(c) => c,
        Err(e) => {
            log_error(&e);
            std::process::exit(1)  // Returns !, coerces to Config
        }
    }
}
```

## `Result::flatten` with `!`/`Infallible` (Rust 1.89+)

`Result::flatten` eliminates manual `match` for nested `Result` types, especially with `!` or `Infallible`:

```rust
use core::convert::Infallible;

// Before: manual match
fn get_first(items: &[Result<i32, Error>]) -> Result<i32, Error> {
    match items.first() {
        Some(Ok(v)) => Ok(*v),
        _ => Err(Error::Empty),
    }
}

// After: flatten with map
fn get_first(items: &[Result<i32, Error>]) -> Result<i32, Error> {
    items.first().copied().unwrap_or(Err(Error::Empty))
}

// Flattening nested Results
// Result<Result<T, E>, E> -> Result<T, E>
let nested: Result<Result<i32, ()>, ()> = Ok(Ok(42));
let flat: Result<i32, ()> = nested.flatten();  // Ok(42)

// Infallible never-type pattern
fn always_ok() -> Result<i32, Infallible> {
    Ok(42)
}

// unused_must_use (Rust 1.92+) no longer warns for Infallible
// because the Err variant can never be constructed:
let _ = always_ok();  // No warning — Err is Infallible
```

## `unused_must_use` + `Infallible` (Rust 1.92+)

Since Rust 1.92, the compiler understands that `Result<T, Infallible>` can never be an `Err`. The `#[must_use]` lint no longer warns when such a result is discarded, because the error case is statically impossible:

```rust
use core::convert::Infallible;

fn compute() -> Result<i32, Infallible> {
    Ok(42)
}

// No warning — Err is Infallible, unreachable
compute();

// With a real error type, the must_use lint applies:
fn fallible() -> Result<i32, Error> {
    Ok(42)
}
// fallible();  // Warning: unused Result that must be used
```

## `From<T> for AssertUnwindSafe<T>` (Rust 1.96+)

`AssertUnwindSafe<T>` now implements `From<T>`, making it ergonomic to opt out of unwind safety in panicking contexts:

```rust
use std::panic::AssertUnwindSafe;

// Before Rust 1.96: manual AssertUnwindSafe constructor
let guarded = AssertUnwindSafe(my_value);

// After Rust 1.96: ergonomic From<T> conversion
let guarded: AssertUnwindSafe<_> = my_value.into();

// Useful with catch_unwind:
use std::panic::catch_unwind;

let result = catch_unwind(AssertUnwindSafe(|| {
    // Code that may panic
    do_fallible_work()
}));
```

## Standard Library Examples

```rust
// std::process::exit
pub fn exit(code: i32) -> !

// panic! macro — expands to ! type expression

// std::hint::unreachable_unchecked
pub unsafe fn unreachable_unchecked() -> !

// loop {} with no break
fn forever() -> ! {
    loop {}
}
```

## In Match Expressions

```rust
enum State { Running, Stopped, Error }

fn get_status(state: &State) -> &str {
    match state {
        State::Running => "running",
        State::Stopped => "stopped",
        State::Error => unreachable!(),  // ! coerces to &str
    }
}
```

## Diverging Closures

```rust
// Closures that never return
let handler: fn() -> ! = || panic!("Handler called");

// In thread spawn
std::thread::spawn(|| -> ! {
    loop { process_work(); }
});
```

## Using `Infallible` on Stable

The `!` type is still nightly-only as a general-purpose type. On stable, use `std::convert::Infallible` — it's the stable equivalent and works with `Result`:

```rust
use std::convert::Infallible;

// Cannot fail — infallible
type NeverResult = Result<(), Infallible>;

fn always_ok() -> NeverResult {
    Ok(())
}
```

## See Also

- [Rust Blog 1.92: Never type lints deny-by-default](https://blog.rust-lang.org/2025/12/11/Rust-1.92.0)
- [Rust 1.89: Result::flatten](https://blog.rust-lang.org/2025/08/07/Rust-1.89.0/)
- [Rust 1.96: AssertUnwindSafe improvements](https://blog.rust-lang.org/2026/05/28/Rust-1.96.0/)
- [err-result-over-panic](./err-result-over-panic.md) — When to panic vs return Result
- [type-result-fallible](./type-result-fallible.md) — `Result` for errors
- [opt-cold-unlikely](./opt-cold-unlikely.md) — Marking unlikely paths
