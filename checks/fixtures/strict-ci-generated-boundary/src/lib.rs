#![expect(
    clippy::missing_safety_doc,
    reason = "fixture represents checked-in generated FFI code"
)]

pub const unsafe fn generated_ffi_entrypoint() {}
