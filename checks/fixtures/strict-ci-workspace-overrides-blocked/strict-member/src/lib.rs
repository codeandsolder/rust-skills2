/// Returns the fixture value.
#[must_use]
pub const fn value() -> u8 {
    1
}

#[cfg(test)]
mod tests {
    #[test]
    fn strict_member_must_not_unwrap() {
        let value = Some(1_u8);
        assert_eq!(value.unwrap(), 1);
    }
}
