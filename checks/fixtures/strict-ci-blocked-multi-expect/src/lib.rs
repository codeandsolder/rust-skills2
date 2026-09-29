//! Negative fixture: one expectation must name only one lint.

/// Deliberately bundles two otherwise-suppressible lints.
#[expect(
    clippy::must_use_candidate,
    clippy::missing_errors_doc,
    reason = "negative fixture: bundled expectations must be rejected"
)]
pub fn bundled_expectations(value: Result<u8, &'static str>) -> Result<u8, &'static str> {
    value
}
