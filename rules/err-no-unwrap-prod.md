# err-no-unwrap-prod

> Avoid `unwrap()` in production code; use `?`, `expect()`, or handle errors

## Why It Matters

`unwrap()` panics on `None` or `Err` without any context about what went wrong. In production, this creates cryptic crash messages that are hard to debug. Either propagate errors with `?`, use `expect()` with a message explaining the invariant, or handle the error explicitly.

## Bad

```rust
fn process_request(req: Request) -> Response {
    let user_id = req.headers.get("X-User-Id").unwrap();  // Why did it fail?
    let user = database.find_user(user_id).unwrap();       // Which operation?
    let data = user.preferences.get("theme").unwrap();     // No context
    
    Response::new(data)
}

// Crash message: "called `Option::unwrap()` on a `None` value"
// Where? Why? No idea.
```

## Good

<!-- rust-check: fragment; reason=extraction artifact: wrapper/context -->
```rust
// Option 1: Propagate with ?
fn process_request(req: Request) -> Result<Response, AppError> {
    let user_id = req.headers
        .get("X-User-Id")
        .ok_or(AppError::MissingHeader("X-User-Id"))?;
    
    let user = database.find_user(user_id)?;
    
    let data = user.preferences
        .get("theme")
        .ok_or(AppError::MissingPreference("theme"))?;
    
    Ok(Response::new(data))
}

// Option 2: expect() for invariants (not user input)
fn get_config_value(&self, key: &str) -> &str {
    self.config
        .get(key)
        .expect("BUG: required config key missing after validation")
}

// Option 3: Provide defaults
fn get_theme(user: &User) -> &str {
    user.preferences
        .get("theme")
        .unwrap_or(&"default")
}

// Option 4: Match for complex handling
fn process_optional(value: Option<Data>) -> ProcessedData {
    match value {
        Some(data) => process(data),
        None => {
            log::warn!("No data provided, using fallback");
            ProcessedData::default()
        }
    }
}
```

## `expect()` vs `unwrap()`

```rust
// Bad: no context
let port = config.get("port").unwrap();

// Better: explains the invariant
let port = config.get("port")
    .expect("config must contain 'port' after validation");

// Best: propagate if it's not truly an invariant
let port = config.get("port")
    .ok_or_else(|| ConfigError::MissingKey("port"))?;
```

## Alternatives to unwrap()

| Situation | Use Instead |
|-----------|-------------|
| Can propagate error | `?` operator |
| Has sensible default | `unwrap_or()`, `unwrap_or_default()` |
| Default requires computation | `unwrap_or_else(\|\| ...)` |
| Internal invariant | `expect("explanation")` |
| Need to handle both cases | `match` or `if let` |

## Clippy Lints

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"      # Deny unwrap() in production code
expect_used = "warn"       # Warn on expect() (stricter)
unwrap_in_result = "deny"  # Avoid unwrap inside Result-returning functions
```

```rust
// Allow in specific places where it's justified
#[allow(clippy::unwrap_used)]
fn definitely_safe() {
    // Unwrap is safe here because...
    let x = Some(5).unwrap();
}
```

## Prefer #[expect] Over #[allow] (Rust 1.80+)

Since Rust 1.80, use `#[expect(clippy::unwrap_used)]` instead of `#[allow(clippy::unwrap_used)]`:

```rust
// Good: warns when unwrap is removed and annotation is stale
#[expect(clippy::unwrap_used, reason = "validated input")]
fn process(value: Option<i32>) -> i32 {
    value.unwrap()
}

// After value becomes infallible, clippy warns:
// "expected lint clippy::unwrap_used has been fulfilled"
// → prompts you to delete the annotation
```

## Rust 1.92+ Changes

### `unused_must_use` with `Infallible`

Since Rust 1.92, `unused_must_use` no longer warns on `Result<(), Infallible>`:

```rust
fn always_ok() -> Result<(), Infallible> {
    Ok(())
}

// No more false positive about unused Result
let _ = always_ok();
```

### `unwrap_used` Catches Fully-Qualified Syntax

Since clippy PR #16489 (Rust 1.93), both forms are caught:

```rust
let a = some_result.unwrap();           // caught
let b = Result::unwrap(some_result);    // also caught since 1.93
```

### `unwrap_in_result` with `Infallible`

Since clippy PR #16711, `unwrap_in_result` correctly handles `Infallible`:

```rust
// No false positive: unwrapping Infallible is safe
fn helper() -> Result<i32, Infallible> {
    let value = Some(42).unwrap(); // no warning
    Ok(value)
}
```

## Clippy `allow-unwrap-types` Config

Whitelist `Mutex::lock().unwrap()` while keeping `unwrap_used` = "deny":

```toml
# clippy.toml
allow-unwrap-types = [
    "std::sync::LockResult<std::sync::MutexGuard<_>>",
    "std::sync::LockResult<std::sync::RwLockReadGuard<_>>",
    "std::sync::LockResult<std::sync::RwLockWriteGuard<_>>",
]
```

## See Also

- [err-result-over-panic](./err-result-over-panic.md) - Return Result instead of panicking
- [err-expect-bugs-only](./err-expect-bugs-only.md) - When expect() is appropriate
- [err-expect-not-allow](./err-expect-not-allow.md) - Prefer #[expect] over #[allow]
- [err-clippy-unwrap-types](./err-clippy-unwrap-types.md) - Configure allow-unwrap-types
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) - Patterns for avoiding unwrap
