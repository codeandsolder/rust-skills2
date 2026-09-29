//! Negative fixture: source-level warn can lower a command-line deny.

/// Deliberately attempts to weaken the strict lint level.
#[warn(clippy::unwrap_used)]
pub fn weakened_lint_level(value: Option<u8>) -> u8 {
    value.unwrap_or_default()
}
