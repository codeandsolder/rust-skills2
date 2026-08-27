# err-try-block-experimental

> `try {}` blocks remain nightly-only; prefer stable `Result`/`Option` contexts unless the scoped expression is worth the nightly dependency

## Why It Matters

A `try { ... }` block creates a local try-propagation context: `?` can short-circuit out of the block rather than out of the enclosing function. This is useful when a function itself should not return the same `Result` or `Option`, but one expression inside it naturally does.

As of Rust 1.98, homogeneous try blocks are still unstable behind `#![feature(try_blocks)]` and are tracked by rust-lang/rust#154391. Do not confuse that feature with RFC 3058 / `try_trait_v2`: the public `Try` and `FromResidual` traits are a separate, still-unstable library API tracked by #84277.

## Bad

```rust
use std::num::ParseIntError;

fn parse_pair_verbose(a: &str, b: &str) -> Result<(i32, i32), ParseIntError> {
    let left = match a.parse::<i32>() {
        Ok(value) => value,
        Err(error) => return Err(error),
    };
    let right = match b.parse::<i32>() {
        Ok(value) => value,
        Err(error) => return Err(error),
    };
    Ok((left, right))
}

fn main() {}
```

Do not reach for nightly syntax just to replace propagation that stable `?` already expresses directly.

## Good on Stable

```rust
use std::num::ParseIntError;

fn parse_pair(a: &str, b: &str) -> Result<(i32, i32), ParseIntError> {
    Ok((a.parse::<i32>()?, b.parse::<i32>()?))
}

fn main() {
    assert_eq!(parse_pair("10", "20").unwrap(), (10, 20));
}
```

If the enclosing function already has the desired try context, ordinary `?` is simpler and stable.

## Good on Nightly: A Scoped Try Context

<!-- rust-check: nightly(try_blocks); reason=try blocks remain unstable on Rust 1.98 -->
```rust
#![feature(try_blocks)]

use std::num::ParseIntError;

fn report_pair(a: &str, b: &str) {
    let parsed: Result<(i32, i32), ParseIntError> = try {
        (a.parse::<i32>()?, b.parse::<i32>()?)
    };

    println!("{parsed:?}");
}

fn main() {
    report_pair("10", "20");
}
```

Here `report_pair` returns `()`, while the local expression has a `Result` propagation context. The explicit result type also makes the homogeneous try type clear.

## Stable Scoped Alternative

A small closure or helper function provides the same control-flow boundary on stable Rust:

```rust
use std::num::ParseIntError;

fn report_pair(a: &str, b: &str) {
    let parsed = (|| -> Result<(i32, i32), ParseIntError> {
        Ok((a.parse::<i32>()?, b.parse::<i32>()?))
    })();

    println!("{parsed:?}");
}

fn main() {
    report_pair("10", "20");
}
```

Prefer a named helper when the logic is substantial or independently meaningful.

## Current Status

| Feature | Rust 1.98 status |
|---|---|
| `?` on supported standard types | Stable |
| homogeneous `try { ... }` | Nightly, `try_blocks`, issue #154391 |
| heterogeneous try-block experiment | Nightly experiment, separate feature/work |
| public `core::ops::Try` / `FromResidual` | Nightly, `try_trait_v2`, issue #84277 |

The fact that the compiler implements `?` does not mean the public `Try` trait API has stabilized.

## When Nightly Try Blocks May Be Worth It

Consider them only when the project already accepts nightly and a local try context materially improves the expression structure, for example when:

- an enclosing function returns a different type but a local computation naturally returns `Result` or `Option`;
- a larger expression should short-circuit locally without extracting a separate helper;
- you are explicitly experimenting with the evolving error-handling language features.

Avoid them when stable `?`, iterator collection, a helper function, or a short closure is equally clear.

## Homogeneous Means the Try Context Matters

Do not advertise current homogeneous try blocks as a magic way to freely mix `Result` and `Option` propagation. `?` must still be compatible with the block's try context. Convert between error/absence representations explicitly when your API requires it.

## See Also

- [err-question-mark](./err-question-mark.md) — Stable `?` propagation
- [err-from-impl](./err-from-impl.md) — `From` conversions for `Result`
- [err-context-chain](./err-context-chain.md) — Adding context to errors
