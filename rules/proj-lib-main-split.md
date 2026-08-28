# proj-lib-main-split

> Put reusable or directly importable application logic in a library target; keep binary entry points thin when that separation helps.

## Why It Matters

A package can contain both a library target (`src/lib.rs`) and one or more binary targets (`src/main.rs`, `src/bin/*.rs`). Moving core logic into the library gives binaries, examples, benchmarks, and integration tests a normal Rust API they can import.

That does **not** mean code in `main.rs` is untestable. Binary targets can contain unit tests, and Cargo integration tests can execute built binaries through `CARGO_BIN_EXE_<name>`. The distinction is about **importable API boundaries and reuse**, not whether testing is possible at all.

A thin binary entry point is especially useful when several binaries share logic, integration tests need to call functions directly, or startup/orchestration code would otherwise bury domain behavior.

## Bad: Domain Logic Exists Only Inside the Binary Target

<!-- rust-check: compile -->
```rust
#[derive(Debug)]
struct Config {
    port: u16,
}

fn parse_config(text: &str) -> Result<Config, &'static str> {
    let port = text.parse::<u16>().map_err(|_| "invalid port")?;
    Ok(Config { port })
}

fn handle_request(config: &Config, request: &str) -> String {
    format!("{}:{}", config.port, request)
}

fn main() -> Result<(), &'static str> {
    let config = parse_config("8080")?;
    println!("{}", handle_request(&config, "health"));
    Ok(())
}
```

This is valid and can have unit tests in the binary target. The limitation is architectural: another target cannot import `parse_config` or `handle_request` through the package's library API because there is no such API.

## Good: Importable Logic, Thin Entrypoint

<!-- rust-check: compile -->
```rust
// In a real package this module body can live in src/lib.rs.
mod my_app {
    #[derive(Debug)]
    pub struct Config {
        pub port: u16,
    }

    impl Config {
        pub fn parse(text: &str) -> Result<Self, &'static str> {
            let port = text.parse::<u16>().map_err(|_| "invalid port")?;
            Ok(Self { port })
        }
    }

    pub fn handle_request(config: &Config, request: &str) -> String {
        format!("{}:{}", config.port, request)
    }

    pub fn run(config: Config) -> Result<(), &'static str> {
        let output = handle_request(&config, "health");
        if output.is_empty() {
            Err("empty response")
        } else {
            Ok(())
        }
    }
}

// src/main.rs would import these from the package library, e.g.
// `use my_app::{Config, run};`.
use my_app::{run, Config};

fn main() -> Result<(), &'static str> {
    let config = Config::parse("8080")?;
    run(config)
}
```

The binary owns process-level concerns—argument parsing, environment setup, logging initialization, exit status—while reusable behavior lives behind a library API.

## What Belongs in `main.rs`?

Keeping `main.rs` "thin" does not mean reducing it to exactly three lines. Binary-specific orchestration can reasonably stay there:

- parse CLI arguments,
- initialize tracing/logging,
- read environment variables,
- choose subcommands,
- construct concrete adapters,
- convert the library's result into an exit code or user-facing diagnostic.

Move logic into the library when callers/tests benefit from importing it or when multiple targets share it. Do not create a public library abstraction for code that is genuinely specific to one tiny executable merely to satisfy a style slogan.

## Direct Library Testing

A library boundary makes ordinary integration tests straightforward because each file in `tests/` is a separate crate that can import the package library's **public** API.

<!-- rust-check: compile -->
```rust
mod my_app {
    #[derive(Debug, PartialEq, Eq)]
    pub struct Config {
        pub port: u16,
    }

    pub fn parse_config(text: &str) -> Result<Config, &'static str> {
        let port = text.parse::<u16>().map_err(|_| "invalid port")?;
        Ok(Config { port })
    }
}

fn integration_style_test() {
    let config = my_app::parse_config("9000").unwrap();
    assert_eq!(config, my_app::Config { port: 9000 });
}
```

In a real `tests/config.rs`, the `my_app` module above is the package library crate itself.

## Binary Integration Tests Still Exist

Cargo also automatically builds binary targets when integration tests need them and sets `CARGO_BIN_EXE_<name>` to the executable path. Such a test can spawn the program and assert on stdout, stderr, files, sockets, or exit status.

That is useful for validating the actual CLI/process boundary. It is usually slower and less surgical than calling library functions directly, so a project often benefits from **both**:

- many direct library tests for behavior,
- a smaller set of end-to-end binary tests for wiring and user-visible behavior.

## Multiple Binaries

A library target becomes particularly valuable when several binaries share domain code.

<!-- rust-check: compile -->
```rust
mod app {
    #[derive(Default)]
    pub struct Store {
        value: u64,
    }

    impl Store {
        pub fn increment(&mut self) -> u64 {
            self.value += 1;
            self.value
        }
    }
}

fn server_entry() {
    let mut store = app::Store::default();
    println!("server value={}", store.increment());
}

fn admin_cli_entry() {
    let mut store = app::Store::default();
    println!("admin value={}", store.increment());
}
```

In a real package these entry functions can live in `src/bin/server.rs` and `src/bin/admin.rs`, both importing `Store` from `src/lib.rs`.

## Library API Does Not Need to Mirror Internal Modules

`src/lib.rs` can define private modules and selectively re-export the stable surface:

<!-- rust-check: compile -->
```rust
mod config {
    pub struct Config {
        pub port: u16,
    }
}

mod engine {
    use super::config::Config;

    pub fn run(config: Config) -> u16 {
        config.port
    }
}

pub use config::Config;
pub use engine::run;
```

This lets internal file/module organization evolve without forcing callers to depend on every internal path.

## Decision Guide

| Situation | Useful structure |
|---|---|
| Tiny single-purpose executable with little reusable logic | Binary-only may be sufficient |
| Domain logic needs direct integration tests/imports | Library + thin binary |
| Several binaries share code | Library + `src/bin/*` binaries |
| Need end-to-end CLI behavior tests | Test the binary via `CARGO_BIN_EXE_<name>` |
| Need both direct logic tests and CLI tests | Library API plus a small binary boundary |

## See Also

- [proj-bin-dir](./proj-bin-dir.md) - Multiple binaries in `src/bin/`
- [proj-mod-by-feature](./proj-mod-by-feature.md) - Module organization
- [test-integration-dir](./test-integration-dir.md) - Cargo integration tests
- [proj-pub-use-reexport](./proj-pub-use-reexport.md) - Curating the library's public surface
