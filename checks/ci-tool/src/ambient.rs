//! Validate ambient configuration guidance against real Clippy JSON diagnostics.
use super::{Result, invalid};
use serde_json::Value;
use std::{collections::BTreeSet, fs, io::BufRead, path::Path};

fn expected_lines(source: &str) -> BTreeSet<usize> {
    source
        .lines()
        .enumerate()
        .filter_map(|(index, line)| {
            line.trim_end_matches('\r')
                .ends_with("// audit")
                .then_some(index + 1)
        })
        .collect()
}

fn diagnostic_lines(source_name: &str, input: impl BufRead) -> Result<BTreeSet<usize>> {
    let mut seen = BTreeSet::new();
    for (line, row) in input.lines().enumerate() {
        let row = row?;
        let record: Value = serde_json::from_str(&row).map_err(|error| {
            invalid(format!(
                "invalid compiler JSON on line {}: {error}",
                line + 1
            ))
        })?;
        if record["reason"] != "compiler-message" {
            continue;
        }
        let diagnostic = &record["message"];
        let code = diagnostic["code"]["code"].as_str().unwrap_or("");
        if code == "unfulfilled_lint_expectations" {
            return Err(invalid(
                "credential boundary expectation did not correspond to an actual finding",
            )
            .into());
        }
        if code != "clippy::disallowed_methods" {
            continue;
        }
        if diagnostic["level"] != "warning" {
            return Err(invalid(format!(
                "advisory unexpectedly became {}",
                diagnostic["level"].as_str().unwrap_or("missing level")
            ))
            .into());
        }
        let spans = diagnostic["spans"]
            .as_array()
            .ok_or_else(|| invalid(format!("missing diagnostic spans on line {}", line + 1)))?;
        for span in spans {
            if span["is_primary"] == true
                && span["file_name"]
                    .as_str()
                    .and_then(|file| file.rsplit(['/', '\\']).next())
                    == Some(source_name)
            {
                let number = span["line_start"]
                    .as_u64()
                    .and_then(|line| usize::try_from(line).ok())
                    .ok_or_else(|| invalid("primary diagnostic has no valid source line"))?;
                seen.insert(number);
            }
        }
    }
    Ok(seen)
}

fn audit(source: &str, name: &str, input: impl BufRead) -> Result<usize> {
    let expected = expected_lines(source);
    let actual = diagnostic_lines(name, input)?;
    if actual != expected {
        return Err(invalid(format!(
            "ambient audit mismatch: expected {expected:?}, observed {actual:?}"
        ))
        .into());
    }
    Ok(actual.len())
}

/// Assert compiler-resolved operations against explicit audit markers.
///
/// # Errors
/// Returns an error for malformed diagnostics, unexpected lint levels, or inventory mismatches.
pub fn verify(root: &Path, input: impl BufRead) -> Result<()> {
    let path = root.join("checks/fixtures/ambient-config-advisory/src/lib.rs");
    let source = fs::read_to_string(&path)?;
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| invalid("ambient fixture source filename is not UTF-8"))?;
    let count = audit(&source, name, input)?;
    println!("OK: {count} compiler-resolved ambient environment operations");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn matched_primary_warnings_and_unrelated_diagnostics() -> Result<()> {
        let input = concat!(
            r#"{"reason":"compiler-message","message":{"code":{"code":"clippy::disallowed_methods"},"level":"warning","spans":[{"is_primary":true,"file_name":"C:\\build\\src\\lib.rs","line_start":2},{"is_primary":false,"file_name":"other.rs","line_start":3}]}}"#,
            "\n",
            r#"{"reason":"compiler-artifact"}"#,
            "\n"
        );
        assert_eq!(
            audit(
                "fn a() {}\r\nfn b() {} // audit\r\n",
                "lib.rs",
                Cursor::new(input)
            )?,
            1
        );
        Ok(())
    }

    #[test]
    fn rejects_missing_warning_wrong_severity_or_unfulfilled_expectation() {
        let source = "fn b() {} // audit\n";
        for input in [
            "",
            r#"{"reason":"compiler-message","message":{"code":{"code":"clippy::disallowed_methods"},"level":"error","spans":[{"is_primary":true,"file_name":"lib.rs","line_start":1}]}}"#,
            r#"{"reason":"compiler-message","message":{"code":{"code":"unfulfilled_lint_expectations"}}}"#,
            "invalid JSON",
        ] {
            assert!(
                audit(source, "lib.rs", Cursor::new(input)).is_err(),
                "{input}"
            );
        }
    }

    #[test]
    fn only_matching_source_and_primary_spans_count() {
        let record = r#"{"reason":"compiler-message","message":{"code":{"code":"clippy::disallowed_methods"},"level":"warning","spans":[{"is_primary":false,"file_name":"lib.rs","line_start":1},{"is_primary":true,"file_name":"unrelated.rs","line_start":1}]}}"#;
        assert!(audit("fn b() {} // audit\n", "lib.rs", Cursor::new(record)).is_err());
    }
}
