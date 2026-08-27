# err-no-std-error

> Use `core::error::Error` for genuine `no_std` error types; current `thiserror` supports this on Rust 1.81+

## Why It Matters

`core::error::Error` has been stable since Rust 1.81, so a `no_std` crate can participate in the standard Rust error ecosystem without importing `std`. Current `thiserror` 2.x is itself a `#![no_std]` crate and has an optional `std` feature, enabled by default.

For a genuinely `no_std` dependency configuration on Rust 1.81+, disable that default feature:

```toml
[dependencies]
thiserror = { version = "2", default-features = false }
```

Then keep the error's field types and formatting expressions compatible with the facilities available to your crate (`core`, plus `alloc` only if the crate enables it).

## Bad

<!-- rust-check: compile -->
```rust
use thiserror::Error;

#[derive(Error, Debug)]
enum DeviceError {
    // This field makes the error depend on std::io. That can be fine for a
    // normal std crate, but it defeats a core-only no_std error definition.
    #[error("I/O failed")]
    Io(#[from] std::io::Error),
}
```

The derive itself is not the problem; the error's dependencies are. A `no_std` crate cannot become portable merely by disabling thiserror's `std` feature while its own public error type still requires `std` types.

## Good

<!-- rust-check: compile -->
```rust
use thiserror::Error;

const SECTOR_COUNT: u32 = 128;
const SECTOR_SIZE: u32 = 4096;

#[derive(Error, Debug)]
pub enum FlashError {
    #[error("flash write protected")]
    WriteProtected,

    #[error("out of bounds at offset {offset} size {size}")]
    OutOfBounds { offset: u32, size: u32 },

    #[error("flash operation timed out")]
    Timeout,
}

fn write_flash(sector: u32, data: &[u8]) -> Result<(), FlashError> {
    if sector >= SECTOR_COUNT {
        return Err(FlashError::OutOfBounds {
            offset: sector.saturating_mul(SECTOR_SIZE),
            size: data.len() as u32,
        });
    }

    Ok(())
}
```

The Rust in this example uses only core-compatible value types. In an actual library crate, put the crate-level attribute in `lib.rs`:

```text
#![no_std]
```

The corpus compile harness checks the Rust example as an ordinary example target; your crate's own CI should additionally compile the real `no_std` target with the intended feature set.

## Manual Implementations Are Also Fine

`thiserror` is a convenience, not a requirement. A small error type can implement `Display` and `core::error::Error` directly:

```rust
use core::fmt;

#[derive(Debug)]
enum FlashError {
    Timeout,
}

impl fmt::Display for FlashError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Timeout => f.write_str("flash operation timed out"),
        }
    }
}

impl core::error::Error for FlashError {}
```

Choose the derive macro for ergonomics, not because handwritten implementations are inherently incorrect.

## `#[from]` and `#[source]` Work with Core Error Types

Define lower-level errors without `std`, then compose them normally:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
#[error("bus transaction failed")]
struct BusError;

#[derive(Error, Debug)]
#[error("invalid descriptor")]
struct DescriptorError;

#[derive(Error, Debug)]
enum UsbError {
    #[error("descriptor read failed")]
    Descriptor(#[from] DescriptorError),

    #[error("transfer failed")]
    Transfer(#[from] BusError),
}
```

A `#[from]` field is also a source. For contextual variants with additional fields, use `#[source]` and construct the variant explicitly:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
#[error("DMA engine fault")]
struct DmaError;

#[derive(Error, Debug)]
enum SpiError {
    #[error("DMA transfer failed on channel {channel}")]
    DmaFailed {
        channel: u8,
        #[source]
        source: DmaError,
    },
}
```

## `std` Feature Nuance in Current `thiserror`

In current `thiserror` 2.x, the default `std` feature primarily enables conveniences that require standard-library types, including direct formatting support for `std::path::{Path, PathBuf}` in error messages. Disabling it keeps the derive crate itself in `no_std` mode.

Current `thiserror` still declares an overall MSRV below 1.81 because its build script falls back to enabling `std` on compilers where `core::error::Error` is unavailable. If your requirement is **genuine no_std error support**, use Rust 1.81 or newer; below that version, disabling the Cargo feature does not provide the same core-error setup.

## Test the Real Feature Combination

A source example compiling with the default dependency graph is not sufficient proof of `no_std` compatibility. Add an explicit CI check for the crate configuration you publish, for example:

```bash
cargo check --no-default-features --target thumbv7em-none-eabihf
```

Use a target that matches the project's support policy. The important part is to build with `std` actually unavailable, not merely to avoid writing `std::` in one file.

## When `alloc` Is Needed

`String`, `Vec`, `Box`, and other heap-backed standard collections live in `alloc` for `no_std` crates. If an error stores owned strings or boxed sources, the crate must opt into `alloc` and have an allocator at runtime. Scalar-only errors like the examples above avoid that requirement.

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Typed errors with `thiserror`
- [err-from-impl](./err-from-impl.md) — `From` / `#[from]`
- [err-source-chain](./err-source-chain.md) — Preserving error sources
