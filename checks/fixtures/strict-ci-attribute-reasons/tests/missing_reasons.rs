#[deprecated(since = "0.1.0")]
#[must_use = "the returned fixture value is the result"]
pub const fn deprecated_without_note() -> u8 {
    1
}

#[must_use]
pub const fn must_use_without_reason() -> u8 {
    2
}

#[test]
fn ordinary_test() {
    assert_eq!(must_use_without_reason(), 2);
}
