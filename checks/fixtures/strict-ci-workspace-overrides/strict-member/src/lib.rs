/// Returns the fixture value.
#[must_use]
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
