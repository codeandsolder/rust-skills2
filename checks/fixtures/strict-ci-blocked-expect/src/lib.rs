//! Negative fixture: CI must reject attempts to expect a non-negotiable lint.

/// Deliberately violates the central policy.
#[expect(
    clippy::unwrap_used,
    reason = "negative fixture: non-negotiable lints must not be suppressible"
)]
pub fn forbidden_suppression(value: Option<u8>) -> u8 {
    value.unwrap()
}
