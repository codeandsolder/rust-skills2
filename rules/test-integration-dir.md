# test-integration-dir

> Put external-API integration tests in Cargo's `tests/` targets

## Why It Matters

Cargo treats top-level integration-test targets under `tests/` as separate crates that depend on the package as an external user would. They can access the library's public API, not its private implementation details.

This complements unit tests inside `src/`: unit tests can exercise private helpers, while integration tests verify that the public package boundary is actually usable.

## Basic Layout

```text
my_project/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   └── internal.rs
└── tests/
    ├── api.rs
    ├── cli.rs
    └── common/
        └── mod.rs
```

A top-level file such as `tests/api.rs` is an integration-test target. Helper modules such as `tests/common/mod.rs` are modules used by a target rather than independent tests merely because they are Rust files.

## Bad: Calling a Unit Test an Integration Test

<!-- rust-check: compile -->
```rust
// This could live in src/lib.rs, but it is a unit test location.
fn public_operation(value: u32) -> u32 {
    value + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_workflow() {
        assert_eq!(public_operation(41), 42);
    }
}

fn main() {}
```

There is nothing wrong with this test; it simply does not test the crate from an external-crate boundary.

## Good: Exercise the Public API

An actual `tests/integration_test.rs` would import the package crate. The following self-contained example defines the same minimal public API locally so this rule's snippet can be compile-checked in isolation:

<!-- rust-check: compile -->
```rust
mod my_crate {
    #[derive(Debug, Clone, Default)]
    pub struct Config {
        strict: bool,
    }

    impl Config {
        pub fn strict() -> Self {
            Self { strict: true }
        }
    }

    #[derive(Debug, PartialEq, Eq)]
    pub enum Error {
        InvalidInput,
    }

    pub struct Client {
        config: Config,
    }

    impl Client {
        pub fn new(config: Config) -> Self {
            Self { config }
        }

        pub fn process(&self, input: &str) -> Result<usize, Error> {
            if self.config.strict && input == "invalid" {
                Err(Error::InvalidInput)
            } else {
                Ok(input.len())
            }
        }
    }
}

use my_crate::{Client, Config, Error};

#[test]
fn full_workflow() {
    let client = Client::new(Config::default());
    assert_eq!(client.process("input"), Ok(5));
}

#[test]
fn error_handling() {
    let client = Client::new(Config::strict());
    assert_eq!(client.process("invalid"), Err(Error::InvalidInput));
}

fn main() {}
```

In the real integration target, the `mod my_crate { ... }` scaffolding is absent and the `use my_crate::...` line resolves to the package's library target.

## Test the Canonical External Contract

An integration test can still false-green if it exercises an alias, fallback, compatibility shim, or synthetic fixture that production clients do not actually use. Prefer the canonical public path, asset name, protocol event, executable, or serialization format that the application ships.

For example, if a web build is expected to publish `pkg/app.js` and `pkg/app_bg.wasm`, the browser test should request those exact assets. Creating extra aliases only for the test can hide a broken production loader while the integration suite remains green.

The same principle applies beyond files:

- test the documented route rather than an internal compatibility route;
- launch the packaged executable rather than calling its private entry helper;
- wait for the application's explicit ready/hello event when that is the public protocol contract;
- use the wire representation a real client sends instead of a more permissive internal type.

The goal is not maximal realism at every layer. It is to make the integration boundary fail when the actual external contract is broken.

## Invalidation Tests Should Reuse the Old Capability

For logout, revocation, token rotation, session-ID rotation, permission removal, or similar invalidation behavior, do not stop after asserting that the invalidation operation returned success. Retain the exact old capability and try to use it again.

A strong regression has this shape:

```text
old = obtain_credential()
assert usable(old)

new = rotate_or_revoke(old)

assert not_usable(old)
assert usable(new)       # when rotation returns a replacement
```

This catches implementations that update bookkeeping or issue a replacement while accidentally leaving the stale credential authorized. Database flags and successful HTTP responses are useful intermediate observations, but the security-relevant contract is whether the old capability still works.

## Shared Test Utilities

Use a module that is not itself a top-level test target:

```text
// tests/common/mod.rs
pub fn fixture() -> String {
    "fixture".to_owned()
}

// tests/api.rs
mod common;

#[test]
fn uses_fixture() {
    assert_eq!(common::fixture(), "fixture");
}
```

`tests/common/mod.rs` is the conventional layout because Cargo does not treat it as another top-level integration-test target.

## Many Integration Tests: Target Count Matters

Each top-level integration-test target is compiled as a separate crate/test executable. Cargo also runs separate test executables as separate targets. If a project accumulates many tiny top-level files, compile/link/startup overhead can become noticeable.

When that matters, group related tests into one target with modules:

```text
// tests/api/main.rs
mod auth;
mod users;
mod orders;

// tests/api/auth.rs
#[test]
fn login_success() {
    // ...
}
```

Here `tests/api/main.rs` is the integration-test target and the sibling files are modules within it.

Choose organization for readability first; consolidate when target proliferation becomes a measured or operational problem.

## Binary Integration Tests

Integration tests can also exercise package binaries. Cargo exposes built binary paths through `CARGO_BIN_EXE_<name>` for integration tests that need to launch them.

For example, an actual integration test for a binary named `my-cli` can use:

```text
let exe = env!("CARGO_BIN_EXE_my-cli");
let output = std::process::Command::new(exe).arg("--help").output()?;
```

That environment variable is supplied by Cargo for the real package test target, so it is shown as text rather than pretending the generic rule harness has a binary named `my-cli`.

## Unit vs Integration Tests

| Unit tests | Integration tests |
|---|---|
| Usually under `src/` with `#[cfg(test)]` | Cargo test targets under `tests/` |
| Can access private implementation | Exercise public crate API |
| Good for focused internal behavior | Good for package-boundary behavior |
| `cargo test --lib` for library unit tests | `cargo test --test <target>` for one integration target |

A project normally wants both rather than forcing all tests into one category.

## Running Tests

```bash
cargo test
cargo test --test api
cargo test --test api login
```

## Alternative Test Runners

`cargo-nextest` is an optional test runner with different scheduling, retry, partitioning, and reporting features. It can improve test throughput in some suites, but do not encode a universal “3× faster” claim: the result depends on test shape, build time, machine, and configuration.

Adopting nextest is separate from the Cargo layout rule. Keep ordinary `cargo test` semantics working unless the project intentionally makes another runner part of its test contract.

## See Also

- [test-cfg-test-module](./test-cfg-test-module.md) - unit test modules
- [test-descriptive-names](./test-descriptive-names.md) - test naming
- [test-tokio-async](./test-tokio-async.md) - async tests
- [test-nextest-workflow](./test-nextest-workflow.md) - nextest-specific workflow
