# type-never-diverge

> Use `!` as the return type of functions that never return normally

**Rule**: `type-never-diverge`

## Why It Matters

The never type `!` has no values. A function returning `!` therefore cannot return normally: it must diverge by looping forever, panicking, terminating the process, or otherwise leaving the current control flow.

Diverging expressions such as `panic!()`, `return`, `break`, and an infinite `loop` can coerce to the type required by their surrounding expression. That is why a panic or process exit can occupy a `match` arm whose other arm produces an ordinary value.

On stable Rust 1.98, `!` is usable in **function return types**, but general-purpose uses such as `Result<T, !>` are still unstable. Use `std::convert::Infallible` when a stable generic type needs an uninhabited error/value type.

## Good: Mark a Diverging Function Explicitly

```rust
fn forever() -> ! {
    loop {
        std::hint::spin_loop();
    }
}

fn fatal(message: &str) -> ! {
    eprintln!("fatal: {message}");
    std::process::exit(1)
}
```

A function that happens not to return today can still use `()`, but `-> !` is stronger documentation and a stronger type-level statement when non-returning behavior is part of the contract.

## Diverging Expressions Coerce to the Needed Type

```rust
fn require_value(value: Option<i32>) -> i32 {
    match value {
        Some(value) => value,
        None => panic!("required value is missing"),
    }
}

fn main() {
    assert_eq!(require_value(Some(7)), 7);
}
```

The `None` arm never produces an `i32`; its diverging expression can therefore coexist with the `i32` produced by the other arm.

The same applies to early exit:

```rust
fn parse_or_exit(text: &str) -> u16 {
    match text.parse() {
        Ok(port) => port,
        Err(error) => {
            eprintln!("invalid port: {error}");
            std::process::exit(2)
        }
    }
}
```

## Stable Generic Uninhabited Type: `Infallible`

General-purpose `!` is not yet stable, so use `Infallible` when a generic position needs a type with no possible values.

```rust
use std::convert::Infallible;

fn fixed_value() -> Result<u32, Infallible> {
    Ok(42)
}

fn main() {
    let value = fixed_value().unwrap();
    assert_eq!(value, 42);
}
```

Do not describe `Infallible` as literally identical to a fully stabilized `!` type today. It fills the common stable generic use case while general-purpose never-type syntax remains experimental.

## `Result::flatten` (Rust 1.89+)

`Result::flatten` removes one level from a nested result **when the inner and outer error types are the same**:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Error {
    Invalid,
}

fn main() {
    let ok: Result<Result<u32, Error>, Error> = Ok(Ok(42));
    assert_eq!(ok.flatten(), Ok(42));

    let inner_error: Result<Result<u32, Error>, Error> = Ok(Err(Error::Invalid));
    assert_eq!(inner_error.flatten(), Err(Error::Invalid));

    let outer_error: Result<Result<u32, Error>, Error> = Err(Error::Invalid);
    assert_eq!(outer_error.flatten(), Err(Error::Invalid));
}
```

Its relevant shape is `Result<Result<T, E>, E> -> Result<T, E>`. It is not specifically an infallibility or never-type API, and it does not flatten nested results with two unrelated error types.

## Rust 1.92 Never-Type Fallback Lints

Rust 1.92 made these two future-compatibility lints deny-by-default:

- `never_type_fallback_flowing_into_unsafe`
- `dependency_on_unit_never_type_fallback`

They detect code whose type inference depends on historical never-type fallback behavior. They are distinct from `unused_must_use` and `dead_code`.

Rust 1.92 also changed `unused_must_use` so it no longer warns for certain `Result<(), Uninhabited>` values, such as `Result<(), Infallible>`. That is a separate lint behavior change, not one of the never-fallback lints above.

When fallback-sensitive inference appears, make the intended type explicit rather than depending on an edition/compiler fallback rule.

```rust
fn choose_unit(early: bool) {
    let _: () = if early {
        return;
    } else {
        Default::default()
    };
}
```

## Standard Diverging Operations

These are ordinary stable examples of APIs/control flow that never return normally:

```rust
fn exit_now() -> ! {
    std::process::exit(1)
}

fn panic_now() -> ! {
    panic!("stop")
}

fn loop_forever() -> ! {
    loop {}
}
```

`std::hint::unreachable_unchecked()` also returns `!`, but it is unsafe: calling it on a reachable execution path is undefined behavior. Prefer safe `unreachable!()` unless you have a proven invariant and a demonstrated reason for the unsafe optimization.

## Do Not Overuse `!`

A function returning `Result<T, E>` or `Option<T>` communicates recoverable failure or absence. Replacing those with a diverging path merely to avoid error handling usually weakens an API.

Use `-> !` when non-returning behavior is genuinely part of the function contract, not as a substitute for normal error propagation.

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — panic versus recoverable errors
- [type-result-fallible](./type-result-fallible.md) — `Result` APIs
- [opt-cold-unlikely](./opt-cold-unlikely.md) — cold error paths
