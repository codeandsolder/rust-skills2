/// Returns the fixture value.
#[must_use = "the returned fixture value is the result"]
pub const fn value() -> u8 {
    1
}

#[cfg(test)]
mod tests {
    #[test]
    fn works() {
        assert_eq!(super::value(), 1);
    }
}
