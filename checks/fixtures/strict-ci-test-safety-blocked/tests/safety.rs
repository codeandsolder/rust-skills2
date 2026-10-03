pub unsafe fn missing_safety_docs() {}

#[test]
fn smoke() {
    let _function: unsafe fn() = missing_safety_docs;
    assert!(true);
}
