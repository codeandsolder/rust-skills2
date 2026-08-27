# err-custom-type

> Define domain error types when callers benefit from knowing what failed

## Why It Matters

A custom error type turns failure modes into structured data. Callers can match variants, inspect fields, decide which failures are retryable, and display a human-readable message without parsing strings.

Do not create a bespoke enum merely for ceremony: at a private application boundary, a context-rich dynamic error may be simpler. Typed errors are most valuable where the failure structure is part of an API contract.

## Good: Model Distinct Failures

```rust
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
enum ValidationError {
    EmptyName,
    NameTooLong { max: usize, actual: usize },
    InvalidAge(u8),
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyName => f.write_str("name cannot be empty"),
            Self::NameTooLong { max, actual } => {
                write!(f, "name has {actual} characters; maximum is {max}")
            }
            Self::InvalidAge(age) => write!(f, "invalid age {age}"),
        }
    }
}

impl std::error::Error for ValidationError {}

struct User {
    name: String,
    age: u8,
}

fn validate(user: &User) -> Result<(), ValidationError> {
    if user.name.is_empty() {
        return Err(ValidationError::EmptyName);
    }
    if user.name.len() > 100 {
        return Err(ValidationError::NameTooLong {
            max: 100,
            actual: user.name.len(),
        });
    }
    if user.age > 120 {
        return Err(ValidationError::InvalidAge(user.age));
    }
    Ok(())
}

fn main() {
    let user = User { name: String::new(), age: 20 };
    assert_eq!(validate(&user), Err(ValidationError::EmptyName));
}
```

The caller can now distinguish programmatically meaningful cases without matching error text.

## Include Data Needed for Handling

```rust
use std::path::PathBuf;

#[derive(Debug)]
enum FileError {
    NotFound { path: PathBuf },
    PermissionDenied { path: PathBuf },
}
```

Fields should support useful decisions or diagnostics. Avoid stuffing every local temporary into the public error type.

## Preserve Sources When Wrapping Errors

If one failure is caused by another error, implement or derive `Error::source` rather than flattening the cause into a string.

```rust
use std::{fmt, io};

#[derive(Debug)]
struct LoadError {
    path: String,
    source: io::Error,
}

impl fmt::Display for LoadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "failed to load {}", self.path)
    }
}

impl std::error::Error for LoadError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.source)
    }
}
```

A derive crate such as `thiserror` can remove this boilerplate without changing the public error semantics.

## `#[non_exhaustive]` for Evolvable Public Enums

A public error enum is part of your compatibility surface. If downstream exhaustive matching would make adding a variant a breaking change, consider `#[non_exhaustive]`.

```rust
#[derive(Debug)]
#[non_exhaustive]
pub enum ApiError {
    RateLimited,
    NotFound,
}
```

This deliberately requires downstream code to include a wildcard arm.

## `thiserror` for Boilerplate

```rust
use thiserror::Error;

#[derive(Debug, Error)]
enum ConfigError {
    #[error("failed to read configuration")]
    Io(#[from] std::io::Error),

    #[error("missing field {0}")]
    MissingField(String),
}
```

Use `#[from]` when conversion from the source error is unambiguous and preserves the semantics you want; use `#[source]` without `#[from]` when construction needs additional context.

## `#[diagnostic::do_not_recommend]` Is Not an Orphan-Rule Escape Hatch

Rust 1.85 stabilized `#[diagnostic::do_not_recommend]` for legal trait impls whose appearance in compiler diagnostics would mislead users. It does not make an illegal blanket conversion legal.

```rust
trait InternalErrorMarker {}
trait PublicErrorMarker {}

#[diagnostic::do_not_recommend]
impl<T: InternalErrorMarker> PublicErrorMarker for T {}

struct DomainError;
impl PublicErrorMarker for DomainError {}

fn main() {}
```

Do not use examples such as implementing `From<T>` for `Box<dyn std::error::Error>`: both the trait and target type are foreign, so such an impl violates coherence regardless of the diagnostic attribute.

For full guidance, see [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md).

## Choose the Error Shape from the Boundary

| Boundary | Typical choice |
|---|---|
| Public library API with actionable failure modes | typed enum/struct |
| Internal application plumbing | often context-rich dynamic error |
| Single wrapped cause plus context | error struct with `source` |
| Public enum expected to gain variants | consider `#[non_exhaustive]` |

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — deriving typed errors
- [err-anyhow-app](./err-anyhow-app.md) — application-oriented dynamic errors
- [err-from-impl](./err-from-impl.md) — conversion rules
- [err-diagnostic-do-not-recommend](./err-diagnostic-do-not-recommend.md) — compiler diagnostic hints
- [api-non-exhaustive](./api-non-exhaustive.md) — evolvable enums
