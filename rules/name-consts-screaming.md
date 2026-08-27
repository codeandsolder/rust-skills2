# name-consts-screaming

> Use `SCREAMING_SNAKE_CASE` for constants and statics

## Why It Matters

Rust convention uses `SCREAMING_SNAKE_CASE` for both `const` and `static` items, making named global values visually distinct from locals and ordinary functions.

The two item kinds are not otherwise interchangeable:

- A `const` names a value evaluated in a const context and is conceptually substituted at each use. Do not rely on a `const` having one unique program-wide address.
- A `static` represents an allocation with a stable shared location and has the `'static` lifetime. Use a static when identity/address or interior-mutability-backed shared state is part of the design.

The Rust Reference generally recommends constants unless the single-address property, interior mutability, or storage of large data makes a static appropriate.

## Bad

<!-- rust-check: compile -->
```rust
#![allow(non_upper_case_globals)]

use std::sync::atomic::AtomicU64;

// These compile when the naming lint is allowed, but violate Rust casing
// conventions for const/static items.
const maxConnections: u32 = 100;
const default_timeout: u64 = 30;
static globalCounter: AtomicU64 = AtomicU64::new(0);
```

Without the `allow`, rustc's `non_upper_case_globals` lint warns about these names.

## Good

<!-- rust-check: compile -->
```rust
use std::sync::{atomic::AtomicU64, OnceLock};
use std::time::Duration;

struct Config;
struct Buffer;

const MAX_CONNECTIONS: u32 = 100;
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);
const BUFFER_SIZE: usize = 4096;

static GLOBAL_COUNTER: AtomicU64 = AtomicU64::new(0);
static CONFIG: OnceLock<Config> = OnceLock::new();

impl Buffer {
    const INITIAL_CAPACITY: usize = 1024;
    const MAX_CAPACITY: usize = 1024 * 1024;
}
```

## Associated Constants

Associated constants use the same casing convention:

```rust
trait Limit {
    const MAX: usize;
    const MIN: usize;
}

struct SmallBuffer;

impl Limit for SmallBuffer {
    const MAX: usize = 256;
    const MIN: usize = 16;
}

struct Container<T> {
    data: Vec<T>,
}

impl<T> Container<T> {
    const EMPTY: Self = Self { data: Vec::new() };
}
```

## Environment and Configuration Keys

The Rust identifier follows Rust casing even when the represented external string follows another convention:

```rust
const ENV_DATABASE_URL: &str = "DATABASE_URL";
const ENV_LOG_LEVEL: &str = "LOG_LEVEL";

const CONFIG_TIMEOUT_SECONDS: &str = "timeout_seconds";
const CONFIG_MAX_RETRIES: &str = "max_retries";
```

## Shared Lazy State with `OnceLock`

When one stable shared instance is actually desired, a static is appropriate:

```rust
use std::sync::OnceLock;

#[derive(Debug)]
struct AppConfig {
    endpoint: String,
}

static CONFIG: OnceLock<AppConfig> = OnceLock::new();

fn config() -> &'static AppConfig {
    CONFIG.get_or_init(|| AppConfig {
        endpoint: "https://example.invalid".into(),
    })
}
```

This is different from a `const`: every access to `CONFIG` refers to the same static allocation.

## Prefer `const` When Identity Is Not Needed

```rust
const RETRY_LIMIT: usize = 3;
const HEADER: &[u8] = b"RUST";

fn should_retry(attempt: usize) -> bool {
    attempt < RETRY_LIMIT
}
```

Use a `static` because you need static identity/storage semantics, not merely because a value is globally named.

## See Also

- [name-funcs-snake](./name-funcs-snake.md) - Function and variable naming
- [name-types-camel](./name-types-camel.md) - Type naming
- [type-newtype-ids](./type-newtype-ids.md) - Type-safe constants
