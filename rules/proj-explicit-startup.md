# proj-explicit-startup

> Initialize application state and register services explicitly at the owning application boundary, not as hidden pre-main or library side effects

## Why It Matters

Implicit startup hooks and global registries hide initialization order,
dependencies, failure handling and resource lifetimes. They can make
independent tests interfere, complicate dynamic loading, and introduce
work before configuration or diagnostics are ready.

## Good: Construct State From Explicit Inputs

<!-- rust-check: run -->
```rust
struct Config {
    workers: std::num::NonZeroUsize,
}

struct Application {
    workers: usize,
}

impl Application {
    fn new(config: Config) -> Self {
        Self { workers: config.workers.get() }
    }
}

fn main() -> Result<(), &'static str> {
    let workers = std::num::NonZeroUsize::new(4).ok_or("invalid worker count")?;
    let application = Application::new(Config { workers });
    assert_eq!(application.workers, 4);
    Ok(())
}
```

The real entry point should parse configuration, initialize observability
and external resources, construct state, run its operation, and coordinate
shutdown. Return startup errors through ordinary fallible interfaces instead
of hiding them in a global initializer. Allow independent instances when
the actual resource contract permits them.

## When Globals Are Justified

Static immutable lookup tables and pure lazy computation can be appropriate.
A process-global subscriber or platform resource may genuinely have one
owner. Establish that ownership explicitly and keep it distinct from
ordinary library calls.

Compiler/linker registration (including distributed slices) can be useful
for a genuine plugin inventory. Distinguish pure declarative registration
data from executable pre-main constructors. If platform constraints
require implicit registration or startup, document ordering, duplicate
registration, link retention, initialization failure and unloading behavior.
Prefer explicit registration when it expresses the same design.

## See Also

- [proj-lib-main-split](./proj-lib-main-split.md)
- [proj-explicit-configuration](./proj-explicit-configuration.md)
- [own-lazy-init](./own-lazy-init.md)
- [obs-library-facade](./obs-library-facade.md)
