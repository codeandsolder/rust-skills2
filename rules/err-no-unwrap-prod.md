# err-no-unwrap-prod

> Avoid `unwrap()` and `expect()`; preserve failures explicitly and encode invariants in types

## Why It Matters

`unwrap()` and `expect()` convert `None` or `Err` into an implicit panic. That is a poor default for user input, I/O, remote services, lookups, parsing, tests, and startup code.

Even when failure would indicate a programmer bug, hidden panic-style extraction makes the failure policy harder to review. For strict AI-maintained code, prefer an explicit error path or a representation that makes the invalid state impossible.

## Bad

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

struct Request {
    headers: HashMap<String, String>,
}

struct Database {
    users: HashMap<String, String>,
}

fn process_request(req: &Request, database: &Database) -> String {
    let user_id = req.headers.get("X-User-Id").unwrap();
    database.users.get(user_id).expect("user should exist").clone()
}

fn main() {}
```

The function silently turns two ordinary lookup failures into panics.

## Good

<!-- rust-check: compile -->
```rust
use std::collections::HashMap;

#[derive(Debug)]
enum AppError {
    MissingHeader,
    UserNotFound,
}

struct Request {
    headers: HashMap<String, String>,
}

struct Database {
    users: HashMap<String, String>,
}

fn process_request(req: &Request, database: &Database) -> Result<String, AppError> {
    let user_id = req
        .headers
        .get("X-User-Id")
        .ok_or(AppError::MissingHeader)?;

    database
        .users
        .get(user_id)
        .cloned()
        .ok_or(AppError::UserNotFound)
}

fn main() {}
```

The caller can now report the problem, retry, choose a fallback, or terminate at an application boundary.

## Defaults Are Different from Panic Extraction

The `unwrap_or*` family is useful when the domain genuinely defines a fallback; these APIs do not panic on `None`/`Err`.

```rust
use std::collections::HashMap;

fn theme(values: &HashMap<String, String>) -> &str {
    values.get("theme").map(String::as_str).unwrap_or("default")
}

fn main() {
    assert_eq!(theme(&HashMap::new()), "default");
}
```

## Encode Validated State Directly

Do not store a map and later `expect()` a key that validation promised would exist. Convert validated input into a type whose fields express the guarantee.

```rust
use std::num::NonZeroU16;

struct ValidatedConfig {
    port: NonZeroU16,
}

impl ValidatedConfig {
    fn new(port: u16) -> Option<Self> {
        NonZeroU16::new(port).map(|port| Self { port })
    }

    const fn port(&self) -> u16 {
        self.port.get()
    }
}

fn main() {
    assert_eq!(ValidatedConfig::new(8080).map(|cfg| cfg.port()), Some(8080));
}
```

## Pick the Operation That Matches the Failure Contract

| Situation | Typical choice |
|---|---|
| Caller can handle the failure | `?` / return `Result` or `Option` |
| Domain defines a fallback | `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` |
| Both branches need substantive behavior | `match`, `if let`, combinators |
| Construction guarantees a property | encode it in a field/newtype/state type |
| Application cannot continue | return an error to the process boundary; print a diagnostic and return `ExitCode` |

Do not replace every `unwrap()` mechanically with `expect()`. A better message does not remove the hidden panic path.

## Clippy Lints

For strict AI-maintained code, make both extraction forms hard errors:

```toml
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
```

In CI, rust-skills2 keeps these lints at `deny` so proc-macro-generated code can manage its internal lint levels, while the source-policy precheck rejects handwritten `#[allow]`, `#[warn]`, and expectations of these non-negotiable lints.

Keep version trivia out of the rule: run current/pinned Clippy and let CI report the exact syntactic cases it recognizes.

## See Also

- [err-result-over-panic](./err-result-over-panic.md) — Return `Result` for failure
- [err-expect-bugs-only](./err-expect-bugs-only.md) — Explicit alternatives to `expect()`
- [err-expect-not-allow](./err-expect-not-allow.md) — Use lint expectations only for suppressible lints
- [err-clippy-unwrap-types](./err-clippy-unwrap-types.md) — Type-specific unwrap policy
- [anti-unwrap-abuse](./anti-unwrap-abuse.md) — Common unwrap anti-patterns
