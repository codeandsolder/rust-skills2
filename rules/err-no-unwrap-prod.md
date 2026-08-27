# err-no-unwrap-prod

> Avoid `unwrap()` for expected runtime failures; reserve panics for deliberate invariants

## Why It Matters

`unwrap()` converts `None` or `Err` into a panic. That is usually the wrong contract for user input, I/O, remote services, lookups, parsing, and other failures callers are expected to encounter. Propagate or handle those failures instead.

An `unwrap()` is not automatically wrong merely because code is "production" code. If the failure would demonstrate a violated internal invariant and the chosen response is to panic, `expect()` with a useful invariant message can be appropriate. The distinction is **expected failure versus bug/invariant failure**, not test versus production source files.

## Bad

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

struct Request {
    headers: HashMap<String, String>,
}

struct User {
    preferences: HashMap<String, String>,
}

struct Database {
    users: HashMap<String, User>,
}

impl Database {
    fn find_user(&self, id: &str) -> Option<&User> {
        self.users.get(id)
    }
}

struct Response(String);

fn process_request(req: &Request, database: &Database) -> Response {
    // All three failures are ordinary runtime conditions, but unwrap turns
    // each one into a panic.
    let user_id = req.headers.get("X-User-Id").unwrap();
    let user = database.find_user(user_id).unwrap();
    let theme = user.preferences.get("theme").unwrap();

    Response(theme.clone())
}
```

The issue is not merely that the panic message is terse. The API has turned recoverable input/state failures into process control flow by panic.

## Good

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

#[derive(Debug)]
enum AppError {
    MissingHeader(&'static str),
    UserNotFound,
    MissingPreference(&'static str),
}

struct Request {
    headers: HashMap<String, String>,
}

struct User {
    preferences: HashMap<String, String>,
}

struct Database {
    users: HashMap<String, User>,
}

impl Database {
    fn find_user(&self, id: &str) -> Result<&User, AppError> {
        self.users.get(id).ok_or(AppError::UserNotFound)
    }
}

struct Response(String);

fn process_request(req: &Request, database: &Database) -> Result<Response, AppError> {
    let user_id = req
        .headers
        .get("X-User-Id")
        .ok_or(AppError::MissingHeader("X-User-Id"))?;

    let user = database.find_user(user_id)?;

    let theme = user
        .preferences
        .get("theme")
        .ok_or(AppError::MissingPreference("theme"))?;

    Ok(Response(theme.clone()))
}

// A default is also fine when the domain actually defines one.
fn get_theme(user: &User) -> &str {
    user.preferences
        .get("theme")
        .map(String::as_str)
        .unwrap_or("default")
}

struct ValidatedConfig {
    values: HashMap<String, String>,
}

impl ValidatedConfig {
    // If construction guarantees that "port" is present, its absence here is
    // a bug in the invariant. Panicking can be a deliberate contract.
    fn port(&self) -> &str {
        self.values
            .get("port")
            .expect("validated config must contain a port")
    }
}
```

## Pick the Operation That Matches the Failure Contract

| Situation | Typical choice |
|-----------|----------------|
| Caller can handle the failure | `?` / return `Result` or `Option` |
| Domain defines a fallback | `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` |
| Both branches need substantive behavior | `match`, `if let`, combinators |
| Missing value means an internal invariant is broken | `expect("invariant ...")` may be appropriate |
| Type-wide policy deliberately panics on one error kind | Consider a narrowly configured lint exemption |

Do not replace every `unwrap()` mechanically with `expect()`. A better message does not make an expected runtime failure into an invariant.

## `expect()` Messages Describe the Invariant

```rust
use std::collections::HashMap;

fn validated_port(config: &HashMap<String, u16>) -> u16 {
    *config
        .get("port")
        .expect("validated configuration must contain 'port'")
}
```

The message should explain why the value is supposed to exist, so a panic identifies which invariant failed.

## Clippy Lints

Projects that intentionally restrict panic-style extraction can enable Clippy's restriction lints:

```toml
# Cargo.toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "warn"
unwrap_in_result = "warn"
```

These are policy lints, not correctness proofs. `unwrap_in_result`, for example, is deliberately broad: a `Result`-returning function can still contain a genuinely invariant-based panic.

For a local justified exception, prefer an expectation that becomes stale when the lint no longer fires:

```rust
#[expect(clippy::unwrap_used, reason = "literal is known to be Some")]
fn known_value() -> i32 {
    Some(5).unwrap()
}
```

For a deliberate policy covering an entire receiver type, see `allow-unwrap-types` in [err-clippy-unwrap-types](./err-clippy-unwrap-types.md).

## Keep Version Trivia Out of the Rule

The exact syntactic cases recognized by Clippy evolve over time. The durable rule is to run the project's pinned/current Clippy version in CI and treat its diagnostics as the source of truth rather than embedding a chronology of individual Clippy PRs here.

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — Return `Result` for expected failure
- [err-expect-bugs-only](./err-expect-bugs-only.md) — `expect()` for bug-class invariants
- [err-expect-not-allow](./err-expect-not-allow.md) — Prefer `#[expect]` over permanent local allows
- [err-clippy-unwrap-types](./err-clippy-unwrap-types.md) — Type-specific unwrap policy
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Common unwrap anti-patterns
