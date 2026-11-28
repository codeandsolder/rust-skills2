//! Compiler-resolved environment API inventory contract.
use std::env as process;
use std::env::var_os as aliased;
mod reexport {
    pub use std::env::vars_os as snapshot;
}

pub fn direct() -> Option<String> {
    std::env::var("DIRECT").ok() // audit
}

pub fn module_alias() -> Vec<(String, String)> {
    process::vars().collect() // audit
}

pub fn import_alias() -> Option<std::ffi::OsString> {
    aliased("ALIAS") // audit
}

pub fn reexport() -> Vec<(std::ffi::OsString, std::ffi::OsString)> {
    reexport::snapshot().collect() // audit
}

pub fn function_value() -> Option<String> {
    let reader = std::env::var::<&str>; // audit
    reader("INDIRECT").ok()
}

pub fn nonambient_operations() -> usize {
    let mut command = std::process::Command::new("test");
    command.env("EXPLICIT_CHILD_INPUT", "value");
    command.env_remove("UNWANTED_CHILD_INPUT");
    let program = env!("CARGO_PKG_NAME");
    program.len() + std::env::args_os().count()
}

#[expect(clippy::disallowed_methods, reason = "explicit credential provider boundary")]
pub fn credentials() -> Option<String> {
    std::env::var("CREDENTIAL").ok()
}

/// Demonstrate a resolved mutation diagnostic without performing a mutation.
///
/// # Safety
/// The caller must guarantee no other thread or library reads or writes the
/// process environment concurrently for the duration of the operation.
pub unsafe fn mutate_environment() {
    // SAFETY: the caller guarantees exclusive environment access.
    unsafe {
        process::set_var("MUTATION", "value"); // audit
        process::remove_var("MUTATION"); // audit
    }
}
