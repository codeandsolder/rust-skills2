//! Correctly annotated attributes must pass even when compiling relaxed tests.

/// An obsolete function with a migration instruction.
#[deprecated(since = "0.1.0", note = "use value() instead")]
#[must_use = "the returned fixture value is the result"]
pub const fn old_value() -> u8 {
    1
}

/// Returns the fixture's value.
#[must_use = "the returned fixture value is the result"]
pub const fn value() -> u8 {
    1
}
