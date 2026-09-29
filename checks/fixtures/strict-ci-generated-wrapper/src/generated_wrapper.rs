#![expect(
    clippy::missing_safety_doc,
    reason = "wrapper scopes lint policy to generated FFI"
)]

include!("generated.rs");
