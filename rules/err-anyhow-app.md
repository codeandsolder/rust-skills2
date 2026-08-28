# err-anyhow-app

> Use `anyhow` at application boundaries when callers need context and reporting more than a stable typed error API

## Why It Matters

Application code often needs to combine errors from many subsystems and report what operation failed. `anyhow::Result<T>` is useful there because `?` can propagate ordinary error types into one report type, while [`Context`] adds the operation-specific information that low-level errors usually lack.

That does **not** make `anyhow` the right answer for every error boundary. If callers are expected to match variants and recover differently, expose a typed error instead. Public library APIs commonly benefit from typed errors; applications and binaries commonly benefit from `anyhow`, but the architectural requirement matters more than the crate label.

## Bad: Erasing Errors Without Adding Context

```rust
use std::error::Error;
use std::fs;

fn load_text(path: &str) -> Result<String, Box<dyn Error>> {
    // The caller gets the OS error, but not what the application was doing.
    Ok(fs::read_to_string(path)?)
}

fn main() {}
```

The problem is not `Box<dyn Error>` by itself. The problem is that an error such as `No such file or directory` may be missing the operational context needed to debug the application.

## Good: Add Context at the Application Boundary

```rust
use anyhow::{Context, Result};
use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize)]
struct Config {
    port: u16,
}

fn load_config(path: &Path) -> Result<Config> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;

    let config = serde_json::from_str(&text)
        .context("failed to parse config as JSON")?;

    Ok(config)
}

fn main() -> Result<()> {
    let _config = load_config(Path::new("config.json"))?;
    Ok(())
}
```

`with_context` is especially useful when constructing the context string needs runtime data: its closure is evaluated only on the error path.

## `anyhow!`, `bail!`, and `ensure!`

Use ad-hoc errors for application-level conditions that do not need a dedicated public error variant:

```rust
use anyhow::{bail, ensure, Result};

fn checked_ratio(total: u64, completed: u64) -> Result<f64> {
    ensure!(completed <= total, "completed count exceeds total count");

    if total == 0 {
        bail!("cannot compute a ratio for an empty total");
    }

    Ok(completed as f64 / total as f64)
}

fn main() -> Result<()> {
    assert_eq!(checked_ratio(4, 2)?, 0.5);
    Ok(())
}
```

`anyhow!(...)` constructs an `anyhow::Error` directly; `bail!(...)` returns one early; `ensure!(condition, ...)` is a compact application-level precondition check that returns an error when the condition is false.

## Choose `context` Versus `with_context`

```rust
use anyhow::{Context, Result};
use std::fs;

fn read_static_path() -> Result<String> {
    fs::read_to_string("config.json")
        .context("failed to read application config")
}

fn read_dynamic_path(path: &str) -> Result<String> {
    fs::read_to_string(path)
        .with_context(|| format!("failed to read {path}"))
}

fn main() {}
```

- `context(value)` receives the context value eagerly. A static `&'static str` is cheap and clear.
- `with_context(|| ...)` computes context only if the underlying operation fails.
- Add information the source error does not already contain. Repeating the same message at every layer makes chains noisy rather than useful.

## Error Propagation Is Not Rollback

Application orchestration often crosses more than one durable system: a database plus a session store, object storage plus a queue, a local transaction plus an external API, and so on. Once an earlier step has committed a side effect, returning an error from a later step does **not** undo that side effect.

For a multi-step operation, define the success invariant before choosing the error plumbing. Prefer, in order:

1. one real transaction when all state lives in the same transactional system;
2. delayed publication, so externally usable state is not exposed until prerequisite writes have succeeded;
3. an explicit compensating action when a later failure must undo an earlier durable write;
4. a durable workflow/outbox/saga when compensation itself must survive crashes or retries.

A simple application-level pattern is:

```text
created = create_first_artifact()?

if let Err(error) = persist_second_artifact() {
    if let Err(cleanup_error) = remove_first_artifact(created) {
        report_cleanup_failure(cleanup_error)
    }
    return Err(error).context("persist second artifact")
}

return_success()
```

The cleanup failure should not silently replace the original failure, but it must be observable: a failed compensation means the system may now contain orphaned or usable partial state.

Do not claim atomicity merely because each individual call returns `Result`. If a framework defers persistence until middleware, drop, flush, commit, or another later lifecycle point, decide whether the operation needs to force that persistence while compensation is still possible.

For security-sensitive issuance—sessions, API keys, refresh tokens, capability URLs—the useful invariant is often stronger than "the request returned an error": **if issuance fails, no credential created specifically for that failed issuance remains usable**.

## Reporting the Chain

```rust
use anyhow::{Context, Result};

fn fail() -> Result<()> {
    std::fs::read_to_string("missing.json")
        .context("failed to load startup configuration")?;
    Ok(())
}

fn main() {
    if let Err(error) = fail() {
        eprintln!("{error:#}");

        for cause in error.chain() {
            eprintln!("caused by: {cause}");
        }
    }
}
```

`Display` (`{error}`) shows the outer report message. Alternate display (`{error:#}`) includes the cause chain in a compact form. Debug formatting can include additional report information such as backtraces when available and enabled.

## Typed Errors Still Matter

Use a typed error when program logic is expected to distinguish failure kinds:

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum LookupError {
    #[error("record not found")]
    NotFound,
    #[error("storage unavailable")]
    Unavailable,
}

fn retryable(error: &LookupError) -> bool {
    matches!(error, LookupError::Unavailable)
}

fn main() {
    assert!(retryable(&LookupError::Unavailable));
}
```

`anyhow::Error` supports downcasting, so crossing into `anyhow` does not immediately destroy all type information. But if routine control flow depends on matching an error type, keeping that type explicit in the function signature is usually clearer.

## Library and Application Boundaries

A common layering is:

```text
library / reusable component
    -> Result<T, DomainError>

binary / service orchestration
    -> anyhow::Result<T>
    -> add operational context while propagating DomainError
```

This is a useful default, not a law. An internal library can reasonably use `anyhow`; a binary can reasonably expose typed errors between subsystems.

## Practical Guidance

- Use `anyhow` when the main consumer of an error is reporting/logging rather than exhaustive matching.
- Add context at abstraction boundaries: what resource, operation, user/request, or configuration step failed?
- Prefer `with_context` when the message needs formatting or other nontrivial work.
- Keep domain errors typed when callers need stable recovery semantics.
- Do not turn every error into a string before wrapping it; preserving the original error keeps the source chain and downcasting information available.
- When orchestration has already committed durable side effects, pair error propagation with a transaction, delayed publication, compensation, or a durable workflow appropriate to the failure model.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) - Typed error definitions
- [err-context-chain](./err-context-chain.md) - Adding useful context
- [err-source-chain](./err-source-chain.md) - Preserving error sources
- [err-question-mark](./err-question-mark.md) - Propagating errors with `?`
