//! Both attribute documentation lints are non-negotiable in handwritten code.

#[expect(
    clippy::deprecated_attributes_without_note,
    reason = "negative fixture must reject suppressing this lint"
)]
#[deprecated(since = "0.1.0")]
pub const fn deprecated_without_note() -> u8 {
    1
}

#[expect(
    clippy::must_use_without_reason,
    reason = "negative fixture must reject suppressing this lint"
)]
#[must_use]
pub const fn must_use_without_reason() -> u8 {
    2
}
