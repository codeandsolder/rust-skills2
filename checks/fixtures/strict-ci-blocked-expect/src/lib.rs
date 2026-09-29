//! Negative fixture: CI must reject attempts to expect a forbidden lint.

/// Deliberately violates the central policy.
#[expect(
    clippy::unwrap_used,
    reason = "negative fixture: forbidden lints must not be suppressible"
)]
pub fn forbidden_suppression(value: Option<u8>) -> u8 {
    value.unwrap()
}
