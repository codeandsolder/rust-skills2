# err-try-block-experimental

> `try {}` blocks are experimental — consider use cases, prefer `?` for now

## Why It Matters

The `try {}` block (RFC #3058, tracking issue #154391) provides a way to create a scope where the `?` operator returns from the block instead of the enclosing function. This is useful when you want to use `?` without making your entire function return `Result`. However, `try` blocks remain experimental as of Rust 1.96 and require a nightly compiler.

## Bad

```rust
// Circumventing the lack of try blocks with manual matching
fn process_items(items: &[Item]) -> Vec<Result<Processed, Error>> {
    items.iter().map(|item| {
        // Can't use ? here because the closure doesn't return Result
        let validated = validate(item);
        if validated.is_err() {
            return Err(validated.unwrap_err());
        }
        let transformed = transform(validated.unwrap());
        if transformed.is_err() {
            return Err(transformed.unwrap_err());
        }
        Ok(transformed.unwrap())
    }).collect()
}
```

## Good (experimental, nightly only)

```rust
#![feature(try_blocks)]

use std::num::ParseIntError;

fn parse_numbers(input: &str) -> Result<Vec<i32>, ParseIntError> {
    let results: Vec<i32> = input
        .split(',')
        .filter_map(|s| {
            // try block allows ? inside a closure
            try { s.trim().parse::<i32>()? }
        })
        .collect();
    Ok(results)
}

// Or without try blocks, using collect:
fn parse_numbers_stable(input: &str) -> Result<Vec<i32>, ParseIntError> {
    input
        .split(',')
        .map(|s| s.trim().parse::<i32>())
        .collect()  // Collects Result<Vec<_>, _> from iterator of Results
}
```

## Current Status (Rust 1.96, May 2026)

| Feature | Status |
|---------|--------|
| `try_trait_v2` | Stabilized |
| `try_blocks` | Experimental (issue #154391) |
| `try_trait_v2` stabilization as `Try` | Goal for 2026 edition cycle |
| Nightly-only | Yes — requires `#![feature(try_blocks)]` |

## When to Consider Using Try Blocks on Nightly

```rust
#![feature(try_blocks)]

// 1. Mixed Result/Option in closures
fn find_valid(items: &[Item]) -> Option<Validated> {
    items.iter().find_map(|item| try {
        let data = fetch(item.id).ok()?;
        validate(data).ok()?
    })
}

// 2. Multi-step fallible logic in one expression
let config = try {
    let path = find_config()?;
    let content = std::fs::read_to_string(path)?;
    let config: Config = toml::from_str(&content)?;
    validate(config)?
};

// 3. Conditional compilation with Result
#[cfg(feature = "strict")]
fn compute() -> Result<i32, Error> {
    try {
        let a = step1()?;
        let b = step2(a)?;
        step3(b)?
    }
}
```

## When to Avoid

- **Stable Rust only** — cannot use `try` blocks at all
- **Simple single-step `?`** — just call `ok_or` / `map_err` directly
- **When `Iterator::collect` already handles conversion** — many iterator operations can already collect `Result` or `Option`
- **When the `?` operator in the enclosing function already works** — don't wrap the whole function body in a `try` block

## Stable Alternatives

```rust
// 1. Use ok_or / map_err for Option operations
fn find_port(config: &Config) -> Result<u16, Error> {
    config.get("port")
        .and_then(|v| v.as_u64())
        .map(|p| p as u16)
        .ok_or_else(|| Error::MissingKey("port"))
}

// 2. Collect from iterator of Results
fn parse_all(inputs: &[&str]) -> Result<Vec<i32>, ParseIntError> {
    inputs.iter().map(|s| s.parse::<i32>()).collect()
}

// 3. Nested functions for scoped error handling
fn process_item(item: &Item) -> Result<Processed, Error> {
    let validated = inner_validate(item)?;
    inner_transform(validated)
}

fn inner_validate(item: &Item) -> Result<Validated, Error> { ... }
fn inner_transform(v: Validated) -> Result<Processed, Error> { ... }
```

## See Also

- [err-question-mark](./err-question-mark.md) — The ? operator (stable)
- [err-from-impl](./err-from-impl.md) — From implementations for ?
- [err-context-chain](./err-context-chain.md) — Adding context to errors
