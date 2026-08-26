# err-no-std-error

> Use `core::error::Error` for `no_std` error types with thiserror 2.0+

## Why It Matters

Since Rust 1.81, `core::error::Error` is stable, making well-typed errors possible in `no_std` environments. Thiserror 2.0+ supports `default-features = false` to opt out of `std` and use `core::error::Error` instead. This lets embedded, WASM, and kernel code use the same ergonomic error patterns as std projects.

## Bad

```rust
// Manual no_std error — verbose and error-prone
#![no_std]

use core::fmt;

#[derive(Debug)]
pub enum FlashError {
    WriteProtected,
    OutOfBounds { offset: u32, size: u32 },
    Timeout,
}

impl fmt::Display for FlashError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WriteProtected => write!(f, "flash write protected"),
            Self::OutOfBounds { offset, size } => {
                write!(f, "out of bounds at offset {} size {}", offset, size)
            }
            Self::Timeout => write!(f, "flash operation timed out"),
        }
    }
}

// Must manually implement core::error::Error
impl core::error::Error for FlashError {}
```

## Good

```toml
# Cargo.toml
[dependencies]
thiserror = { version = "2", default-features = false }
```

<!-- rust-check: fragment; reason=standalone fragment: unresolved context -->
```rust
//! #![no_std] crate
#![no_std]

use thiserror::Error;

#[derive(Error, Debug)]
pub enum FlashError {
    #[error("flash write protected")]
    WriteProtected,

    #[error("out of bounds at offset {offset} size {size}")]
    OutOfBounds { offset: u32, size: u32 },

    #[error("flash operation timed out")]
    Timeout,
}

// core::error::Error is automatically derived
// Usage with Result:
fn write_flash(sector: u32, data: &[u8]) -> Result<(), FlashError> {
    if sector >= SECTOR_COUNT {
        return Err(FlashError::OutOfBounds {
            offset: sector * SECTOR_SIZE,
            size: data.len() as u32,
        });
    }
    // ...
    Ok(())
}
```

## Serialize/Deserialize in no_std

When using serde alongside thiserror in `no_std`:

```toml
[dependencies]
thiserror = { version = "2", default-features = false }
serde = { version = "1", default-features = false, features = ["derive"] }
```

## #[from] in no_std

`#[from]` works with thiserror 2.0 and Rust 1.81+ in `no_std`:

```rust
#![no_std]

use thiserror::Error;

#[derive(Error, Debug)]
pub enum UsbError {
    #[error("descriptor read failed")]
    DescriptorRead(#[from] DescriptorError),

    #[error("transfer failed")]
    Transfer(#[from] TransferError),
}
```

## Source Chaining in no_std

```rust
#![no_std]

use thiserror::Error;

#[derive(Error, Debug)]
pub enum SpiError {
    #[error("DMA transfer failed on channel {channel}")]
    DmaFailed {
        channel: u8,
        #[source]
        source: DmaError,
    },

    #[error("CS assertion failed")]
    CsAssert(#[from] GpioError),
}
```

## no_std + Error Compatibility Table

| Feature | Rust Version | thiserror Version | Default |
|---------|-------------|-------------------|---------|
| `core::error::Error` | 1.81+ | 2.0+ | enabled with `std` feature |
| `no_std` without `core::error::Error` | 1.0+ | 1.x | N/A |
| `no_std` with `core::error::Error` | 1.81+ | 2.0+ (`default-features = false`) | opt-in |

## When to Avoid

- When targeting Rust versions below 1.81. Use thiserror 1.x and implement display manually.
- When the `std` error trait is genuinely unnecessary (e.g., infallible operations).

## See Also

- [err-thiserror-lib](./err-thiserror-lib.md) — Using thiserror for libraries
- [err-from-impl](./err-from-impl.md) — From implementations with #[from]
- [err-source-chain](./err-source-chain.md) — Preserving error chains with #[source]
