# obs-library-facade

> Reusable libraries should emit observability data without surprising callers by installing process-global logging or tracing state

## Why It Matters

Global logger/subscriber installation is process-wide coordination. A reusable library that silently performs it can conflict with the application, tests, other libraries, or embedding environments that need different filtering, formatting, destinations, or subscriber composition.

The durable split is:

- reusable library code **emits** events/spans through a facade such as `tracing` or `log`;
- the application or embedding layer that owns process startup normally chooses and installs the global collector/logger;
- a library may expose an **explicit opt-in helper** when convenient, but should not install global state as an incidental side effect of ordinary API calls.

## Bad: Hidden Global Setup in Library Work

<!-- rust-check: compile -->
```rust
use tracing::info;

pub fn connect(url: &str) {
    // Bad library behavior: ordinary work unexpectedly claims global setup.
    tracing_subscriber::fmt::init();
    info!(url, "connecting");
}
```

Whether repeated global initialization panics or returns an error depends on the setup API used. The design problem is the surprise and loss of caller control, not one universal failure mode.

## Good: Library Emits, Application Configures

<!-- rust-check: compile -->
```rust
mod mylib {
    use tracing::info;

    pub fn connect(url: &str) {
        info!(url, "connecting");
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init()?;

    mylib::connect("postgres://localhost/app");
    Ok(())
}
```

The binary owns the policy. Library events still work when the application chooses a completely different subscriber stack.

## Explicit Convenience Setup Can Be Fine

A crate that serves both as a library and as tooling support may offer an explicitly named helper. Prefer a fallible operation so existing process-global state is not converted into a panic:

```rust
pub fn try_init_default_tracing(
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init()
}
```

The key is that callers choose to invoke this API. Do not bury it in `Client::new`, `connect`, parsing, or unrelated initialization.

## Tests and Examples

Tests that want human-readable tracing may call `try_init()` and tolerate a prior installation because several tests can share one process:

```rust
fn init_test_tracing() {
    let _ = tracing_subscriber::fmt()
        .with_test_writer()
        .try_init();
}

#[test]
fn emits_a_trace() {
    init_test_tracing();
    tracing::info!("test event");
}
```

For more isolation, use scoped/subscriber APIs rather than relying on mutable global state.

## Dependency Boundary

A reusable library that merely emits `tracing` events generally needs only `tracing` in normal dependencies. Subscriber implementations can stay in the application, examples, or dev-dependencies unless the library intentionally exposes subscriber-building functionality.

```toml
[dependencies]
tracing = "0.1"

[dev-dependencies]
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

The same architectural principle applies to the `log` facade: emission can be a library concern; process-global logger policy normally belongs to the executable or embedding application.

## Key Points

- Do not install process-global observability state as a hidden side effect of ordinary reusable-library calls.
- Emit through a facade and let the application choose collection/filtering/output policy.
- Explicit opt-in setup helpers are different from implicit initialization.
- Prefer fallible initialization APIs when setup may already have occurred.
- Keep subscriber implementation dependencies out of the runtime library dependency graph unless the public API actually needs them.

## See Also

- [obs-tracing-over-log](obs-tracing-over-log.md) - structured tracing
- [obs-levels-filter](obs-levels-filter.md) - application filtering policy
- [api-serde-optional](api-serde-optional.md) - optional dependency boundaries
