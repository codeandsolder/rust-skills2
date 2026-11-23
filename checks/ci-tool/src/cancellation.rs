//! Runtime acceptance contracts generated from the documented recommended example.
use super::{Result, invalid};
use std::{fs, path::Path};

const TESTS: &str = include_str!("../templates/cancellation_tests.rs");

fn extract(source: &str) -> Result<String> {
    let normalized = source.replace("\r\n", "\n").replace('\r', "\n");
    let good = normalized
        .split_once("## Good\n")
        .ok_or_else(|| invalid("cancellation rule lacks a Good section"))?
        .1;
    let section = good
        .split_once("\n## ")
        .map_or(good, |(section, _)| section);
    let after = section
        .split_once("```rust\n")
        .ok_or_else(|| invalid("cancellation Good section lacks a Rust example"))?
        .1;
    let source = after
        .split_once("\n```")
        .ok_or_else(|| invalid("cancellation Rust example is not terminated"))?
        .0;
    Ok(format!("{source}\n{TESTS}"))
}

/// Generate executable regression tests for the actual cancellation example.
///
/// # Errors
/// Returns an error for malformed input or filesystem failures.
pub fn generate(root: &Path, output: &Path) -> Result<()> {
    let source = fs::read_to_string(root.join("rules/async-cancel-safety.md"))?;
    let generated = extract(&source)?;
    let parent = output
        .parent()
        .ok_or_else(|| invalid("output has no parent directory"))?;
    fs::create_dir_all(parent)?;
    if output.exists() {
        return Err(invalid(format!(
            "refusing to overwrite existing runtime contract: {}",
            output.display()
        ))
        .into());
    }
    fs::write(output, generated)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_first_rust_example_in_good_section() -> Result<()> {
        let source = "## Bad\n```rust\nbad()\n```\n## Good\ntext\n```rust\nfn good_example() {}\n```\n```rust\nignored()\n```\n## More\n";
        let code = extract(source)?;
        assert!(code.starts_with("fn good_example() {}\n"));
        assert!(!code.contains("ignored()"));
        assert!(!code.contains("bad()"));
        assert!(code.contains("async fn partial_read_survives_message_branch"));
        Ok(())
    }

    #[test]
    fn rejects_missing_and_unterminated_good_examples() {
        for bad in [
            "",
            "## Bad\n```rust\nbad()\n```\n",
            "## Good\n```rust\nfn f() {}\n",
            "## Good\n```text\nnot rust\n```\n",
        ] {
            assert!(extract(bad).is_err(), "accepted invalid example {bad:?}");
        }
    }
}
