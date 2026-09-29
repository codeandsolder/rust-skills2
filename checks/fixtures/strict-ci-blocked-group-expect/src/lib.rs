//! Negative fixture: correctness expectations must be rejected before Clippy.

/// Deliberately hides a correctness lint.
#[expect(
    clippy::eq_op,
    reason = "negative fixture: correctness expectations must be blocked"
)]
pub fn hidden_correctness_issue(value: u8) -> bool {
    value == value
}
