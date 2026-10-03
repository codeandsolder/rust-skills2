fn same_value(value: u8) -> bool {
    value == value
}

#[test]
fn correctness_lints_stay_fatal() {
    assert!(same_value(1));
}
