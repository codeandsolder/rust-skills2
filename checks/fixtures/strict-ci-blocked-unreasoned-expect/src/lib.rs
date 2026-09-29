//! Negative fixture: every expectation must explain why it exists.

/// Deliberately uses an unreasoned suppressible expectation.
#[expect(clippy::must_use_candidate)]
pub fn unreasoned_expectation(value: u8) -> u8 {
    value
}
