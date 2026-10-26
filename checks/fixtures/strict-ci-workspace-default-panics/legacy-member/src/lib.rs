/// Returns whether the fixture environment variable exists.
#[must_use]
pub fn value() -> bool {
    std::env::var_os("STRICT_CI_UNUSED").is_some()
}

#[cfg(test)]
mod tests {
    #[test]
    fn inherited_test_can_unwrap() {
        let value = Some(1_u8);
        assert_eq!(value.unwrap(), 1);
    }
}
