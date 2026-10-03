#[must_use]
pub const fn maybe_identity(value: usize) -> Option<usize> {
    if value == 0 { None } else { Some(value) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panic_style_test_assertions_are_allowed_by_opt_in() {
        assert_eq!(maybe_identity(7).unwrap(), 7);
        let parsed = "11".parse::<usize>().expect("literal integer parses");
        const EXPECTED: usize = 11;
        assert_eq!(parsed, EXPECTED);
    }
}
