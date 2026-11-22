//! Negative fixture: Cargo rustflags may not cap strict lint levels.

/// Harmless code: the fixture must fail in policy preflight, not Clippy.
#[must_use = "the returned value is the result"]
pub const fn identity(value: u8) -> u8 {
    value
}
