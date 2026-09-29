//! Negative fixture: direct Result/Option expectation is forbidden.

/// Deliberately violates the central no-expect policy.
pub fn forbidden_expect(value: Result<u8, &'static str>) -> u8 {
    value.expect("negative fixture: Result::expect must fail the strict gate")
}
