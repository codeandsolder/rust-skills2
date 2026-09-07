# pat-if-let-chains

> Use `if let` / `while let` chains to combine pattern bindings and conditions, and Rust 1.95+ `if let` guards inside `match` when an arm needs an additional fallible pattern check

## Why It Matters

Let chains (stabilized in Rust 1.88 under the 2024 edition) let you write a single `if` or `while` header that binds multiple patterns and tests arbitrary boolean conditions, all with `&&`. Without chains, each additional binding requires another level of nesting, pushing the happy-path body further right and forcing the reader to track multiple scopes. With chains, all preconditions read left-to-right at the same indentation level.

Rust 1.95 extends the same idea to `match` guards: an arm can use `if let PAT = EXPR` and bind values for use in the arm body. This is useful when the primary dispatch belongs in `match`, but a particular arm has one more fallible/pattern-matching prerequisite.

## Prerequisite

Let chains require the **2024 edition**. Set it in `Cargo.toml`:

```toml
[package]
edition = "2024"
```

The `match` `if let` guard form is available on Rust 1.95+.

## Bad

```rust
fn handle(input: Option<String>, limit: Option<u32>) -> Option<String> {
    if let Some(s) = input {
        if let Ok(n) = s.trim().parse::<u32>() {
            if let Some(max) = limit {
                if n <= max {
                    return Some(format!("valid: {n}"));
                }
            }
        }
    }
    None
}
```

## Good

```rust
fn handle(input: Option<String>, limit: Option<u32>) -> Option<String> {
    if let Some(s) = input
        && let Ok(n) = s.trim().parse::<u32>()
        && let Some(max) = limit
        && n <= max
    {
        return Some(format!("valid: {n}"));
    }
    None
}
```

Each `&&` clause is evaluated in order; short-circuit semantics still apply, so later clauses only run if earlier ones succeed.

## `while let` Chains

The same `&&` chaining works in `while` loop conditions:

```rust
fn process_until_done(stream: &mut impl Iterator<Item = Option<u32>>) {
    while let Some(Some(n)) = stream.next()
        && let Ok(processed) = try_process(n)
        && processed > 0
    {
        println!("processed: {processed}");
    }
}
```

## Rust 1.95+: `if let` Guards in `match`

Use an `if let` guard when the outer pattern is the natural dispatch key but entering one arm also depends on another pattern match:

```rust
fn describe(value: Option<&str>) -> &'static str {
    match value {
        Some(text) if let Ok(number) = text.parse::<u32>() && number > 100 => "large number",
        Some(_) => "other text",
        None => "missing",
    }
}
```

Bindings introduced by the guard are available in that arm's body:

```rust
match value {
    Some(x) if let Ok(y) = compute(x) => {
        use_pair(x, y);
    }
    _ => {}
}
```

### Guard Patterns Do Not Make the Match Exhaustive

A pattern inside a guard is a condition, not another exhaustiveness-covered arm pattern. The compiler does **not** use `if let` guard patterns when deciding whether the `match` is exhaustive.

Therefore this still needs a fallback arm:

```rust
match value {
    Some(x) if let Ok(y) = compute(x) => use_pair(x, y),
    Some(_) => handle_uncomputed(),
    None => handle_missing(),
}
```

Do not write code whose apparent coverage depends on a guard pattern being counted by exhaustiveness analysis.

## Top-Level Constraint for Let Chains

`let` expressions in an `if`/`while` chain must appear at the top level of the condition — they cannot be wrapped in parentheses or grouped with `||`. Only `&&` chaining is supported:

```rust
// ✅ Valid: top-level && chains
if let Some(a) = first()
    && let Some(b) = second()
    && a < b
{ ... }

// ❌ Invalid: parentheses wrapping a let
// if (let Some(a) = first() && let Some(b) = second()) { ... }

// ❌ Invalid: || between let bindings
// if let Some(a) = first() || let Some(b) = second() { ... }
```

## Mixing Patterns and Boolean Guards

Chains can freely interleave `let` bindings with plain boolean expressions:

```rust
struct Config {
    debug: bool,
    timeout: Option<u64>,
}

fn effective_timeout(cfg: &Config) -> Option<u64> {
    if cfg.debug
        && let Some(t) = cfg.timeout
        && t > 0
    {
        Some(t)
    } else {
        None
    }
}
```

## When to Prefer `let ... else`

Use `let ... else` when the goal is early return on failure; use `if let` / `while let` chains when you have a richer condition that combines multiple optional bindings with a positive body to execute. Use a `match` `if let` guard when the outer enum/pattern dispatch should remain visibly exhaustive and one arm has an extra fallible condition.

## See Also

- [pat-let-else](pat-let-else.md) - early-return pattern extraction without nesting
- [pat-matches-macro](pat-matches-macro.md) - boolean pattern tests with `matches!()`
- [pat-exhaustive-enum](pat-exhaustive-enum.md) - exhaustive matching and future-proof enum handling