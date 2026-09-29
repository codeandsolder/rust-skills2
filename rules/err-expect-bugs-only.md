# err-expect-bugs-only

> Avoid `expect()` even for invariants; encode the invariant, propagate failure, or terminate deliberately at the process boundary

## Why It Matters

`expect()` is still an implicit panic. A useful message makes the panic easier to diagnose, but it does not make abrupt unwinding a better API or control-flow boundary.

For AI-maintained code, the implementation cost of handling the case explicitly is small. Prefer to make invalid states unrepresentable, preserve failure as `Result`/`Option`, or convert the failure into a clear diagnostic at the application's outer boundary.

This also keeps one policy across libraries, binaries, tests, and benchmarks: callers can see where failure is handled instead of finding hidden panic paths later.

## Bad

```rust
use std::fs;

fn parse_port(input: &str) -> u16 {
    input.parse().expect("port should parse")
}

fn load_config(path: &str) -> String {
    fs::read_to_string(path).expect("config should exist")
}

fn main() {}
```

Both operations can fail at runtime, and `expect()` converts those failures into implicit process control flow.

## Good: Preserve the Failure

```rust
use std::fs;
use std::io;
use std::num::ParseIntError;

fn parse_port(input: &str) -> Result<u16, ParseIntError> {
    input.parse()
}

fn load_config(path: &str) -> Result<String, io::Error> {
    fs::read_to_string(path)
}

fn main() {}
```

Let the caller decide whether to retry, fall back, report the error, or terminate.

## Good: Encode the Invariant in the Type

If construction guarantees a property, store that property directly instead of repeatedly extracting from a fallible container.

```rust
use std::num::NonZeroU16;

#[derive(Clone, Copy)]
struct ValidatedPort(NonZeroU16);

impl ValidatedPort {
    fn new(port: u16) -> Option<Self> {
        NonZeroU16::new(port).map(Self)
    }

    const fn get(self) -> u16 {
        self.0.get()
    }
}

fn main() {
    assert_eq!(ValidatedPort::new(8080).map(ValidatedPort::get), Some(8080));
}
```

A missing or zero port is rejected at construction, so later code does not need `expect()` to recover a promised invariant.

## Good: Terminate Deliberately at the Application Boundary

A binary may decide that startup cannot continue. Make that policy visible at the boundary and return an exit status after producing a useful diagnostic.

```rust
use std::process::ExitCode;

fn run() -> Result<(), &'static str> {
    Err("required configuration is missing")
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("fatal: {error}");
            ExitCode::FAILURE
        }
    }
}
```

This is preferable to burying an `expect()` deep in startup code. The same pattern works for benchmark harnesses and one-shot tools.

## Good: Tests Return Errors Too

Tests do not need `unwrap()` or `expect()` merely to fail loudly.

```rust
#[test]
fn parses_valid_port() -> Result<(), std::num::ParseIntError> {
    let port: u16 = "8080".parse()?;
    assert_eq!(port, 8080);
    Ok(())
}
```

For `Option`, compare it directly, use pattern matching, or convert it to a test error.

## Source-Code Constants

Before using `expect()` for a hard-coded value, check whether the type already provides a constant or infallible constructor. For example, prefer `std::net::Ipv4Addr::LOCALHOST` over parsing the string `"127.0.0.1"`.

If a hard-coded value genuinely requires fallible initialization, keep the fallibility explicit in the initialization path rather than hiding it behind a panic.

## Linting Policy

For strict AI development, make panic-style extraction non-suppressible in CI:

```text
-Fclippy::unwrap_used
-Fclippy::expect_used
-Fclippy::panic
```

`forbid` is intentional: a local `#[allow]` or `#[expect]` must not turn an implicit abort back on.

The rust-skills2 reusable strict gate applies this policy centrally.

## Decision Guide

| Situation | Prefer |
|---|---|
| invalid user/request input | validation + `Result` |
| missing/failed external resource | `Result`, retry, or fallback |
| network/service failure | `Result`, retry, or fallback |
| internal invariant | encode it in types/state; otherwise return an explicit invariant error |
| hard-coded source data | infallible constant/constructor where available; otherwise explicit initialization error |
| unsupported startup environment | diagnostic + `ExitCode` at the application boundary |
| test fixture unexpectedly invalid | test returns `Result`, pattern match, or assert on the `Result`/`Option` itself |

## Practical Guidance

- Do not mechanically replace `unwrap()` with `expect()`; both hide a panic path.
- Push recoverable failures upward with `?`.
- Push invariant guarantees downward into constructors and types.
- Keep process termination in `main`/the top-level runner where the policy is obvious.
- Prefer returning `ExitCode` from `main` over calling `process::exit` from deep code.
- Tests can return `Result`; benchmarks can print a fatal setup error and return/exit at their harness boundary.

## See Also

- [err-no-unwrap-prod](./err-no-unwrap-prod.md) - Avoid panic-style extraction
- [err-expect-not-allow](./err-expect-not-allow.md) - Narrow lint expectations, not `Result::expect`
- [err-result-over-panic](./err-result-over-panic.md) - Choosing `Result` over panic
- [api-parse-dont-validate](./api-parse-dont-validate.md) - Type-driven validation
