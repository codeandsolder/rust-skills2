//! Minimal crate used to prove that the reusable strict policy can pass.

/// Adds two small integers.
#[must_use]
pub const fn add(left: u8, right: u8) -> u8 {
    left.saturating_add(right)
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn saturates_at_u8_max() {
        assert_eq!(add(250, 10), u8::MAX);
    }
}
