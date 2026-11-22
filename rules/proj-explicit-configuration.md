# proj-explicit-configuration

> Parse configuration at application boundaries and pass typed values explicitly; never use the process environment as a hidden library or algorithm parameter.

## Why It Matters

Ambient process state hides inputs from the type system, prevents independently configured instances from coexisting, and makes results depend on how a process happened to be launched. Repeated environment lookups also introduce unnecessary work, especially in rendering, numerical algorithms, and request loops. Caching a lookup in a global changes its timing but does not make the dependency explicit.

## Bad

<!-- rust-check: compile -->
```rust
fn permits_batch(count: usize) -> bool {
    let limit = std::env::var("APP_BATCH_LIMIT")
        .ok()
        .and_then(|raw| raw.parse::<usize>().ok())
        .unwrap_or(64);
    count <= limit
}
```

This silently changes behavior for every caller and treats malformed configuration as if it were absent.

## Good

<!-- rust-check: compile -->
```rust
use std::num::NonZeroUsize;

#[derive(Clone, Copy)]
struct BatchPolicy {
    limit: NonZeroUsize,
}

impl BatchPolicy {
    fn permits(self, count: usize) -> bool {
        count <= self.limit.get()
    }
}

fn run(limit: NonZeroUsize, count: usize) -> bool {
    BatchPolicy { limit }.permits(count)
}
```

Parse an explicit CLI argument or configuration file once in the executable, reject malformed values, and pass the validated policy into the application. An independently configured caller can construct another policy without changing global state. Do not introduce a configuration struct for a single independent parameter if passing that parameter suffices.

## Boundaries and exceptions

- Use explicit CLI arguments for one-shot commands, fixtures and benchmarks; use typed configuration files for durable service settings. Keep defaults in one authoritative location.
- Use tracing events and scoped subscribers for diagnostics, rather than project-specific environment checks scattered through algorithms. A conventional log filter at subscriber initialization is a legitimate boundary.
- Choose production algorithms deterministically. Keep genuinely supported strategies explicit; remove obsolete experimental switches, rather than adding an environment-reading compatibility wrapper.
- Keep secrets out of command-line arguments. Credential providers, OS conventions (PATH, HOME, XDG directories), platform contracts, and Cargo-provided build/test values may legitimately use the environment at their real integration boundary.
- Tools that model, forward, or fingerprint a process environment may read it as their domain input. Do not bypass the compiler cache or drop actual build dependencies to avoid environment reads.
- Do not mutate the process environment to configure ordinary tests. Construct configuration directly or set the environment of a child process when testing an actual environment contract.
- Compile-time Cargo metadata such as CARGO_PKG_VERSION and CARGO_BIN_EXE_* is not a runtime configuration smell. An arbitrary project-specific compile-time switch still needs a reproducible declared build input.

## Review and enforcement

Review the resolved API and its purpose, including imported aliases, reexports, indirect helper calls, and dependencies on global configuration. A text search is an inventory, not proof of a violation or absence. A compiler-resolved disallowed-method policy can enforce a boundary in a crate whose role is known; a universal ban would break legitimate integration tools. Start fleet migration with advisory findings and enforce only policies that distinguish the actual contract.

## See Also

- [proj-lib-main-split](./proj-lib-main-split.md) - Application and library boundaries
- [proj-build-rs-minimal](./proj-build-rs-minimal.md) - Declared build inputs
- [obs-tracing-over-log](./obs-tracing-over-log.md) - Structured diagnostics
- [test-fixture-raii](./test-fixture-raii.md) - Test isolation
