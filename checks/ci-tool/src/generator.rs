//! Extract checked Rust examples and expectation metadata from rule Markdown.
//! This is a first-party CI tool; all corpus and fixture paths are explicit.
use super::{Result, invalid};
use regex::Regex;
use serde::{Serialize, Serializer, ser::SerializeMap};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write,
    fs,
    path::Path,
};

const HEADER: &str = "#![allow(unused, dead_code, unreachable_code, unused_imports, unused_variables, unused_mut, unused_assignments, unused_macros, non_local_definitions)]\n";

#[derive(Debug, Serialize)]
struct Example {
    file: String,
    line: usize,
    section: String,
    expect: String,
    reason: String,
    generated: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    stable_run: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    nightly_run: Option<bool>,
}

#[derive(Default)]
struct Outputs {
    manifest: Vec<(String, Example)>,
    stable: Vec<(String, String)>,
    nightly: Vec<(String, String)>,
}

struct OrderedManifest<'a>(&'a [(String, Example)]);

impl Serialize for OrderedManifest<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        let mut object = serializer.serialize_map(Some(self.0.len()))?;
        for (name, example) in self.0 {
            object.serialize_entry(name, example)?;
        }
        object.end()
    }
}

struct Patterns {
    marker: Regex,
    fence: Regex,
    heading: Regex,
    main: Regex,
    module: Regex,
}

impl Patterns {
    fn new() -> Result<Self> {
        Ok(Self {
            marker: Regex::new(
                r"^<!--\s*rust-check:\s*(compile|run|fragment|compile_fail|ignore|nightly(?:\([^)]*\))?|fixture\([A-Za-z0-9_-]+\))(?:\s*;\s*reason=(.*?))?\s*-->$",
            )?,
            fence: Regex::new(r"^```rust(?P<attrs>\s*(?:,[^`]*)?)\s*$")?,
            heading: Regex::new(r"^#{2,}\s+(.*)")?,
            main: Regex::new(r"\bfn\s+main\s*\(")?,
            module: Regex::new(r"(?m)^\s*(pub(\([^)]*\))?\s+)?mod\s+\w")?,
        })
    }
}

fn attributes(raw: &str) -> BTreeSet<&str> {
    raw.trim()
        .strip_prefix(',')
        .unwrap_or_else(|| raw.trim())
        .split(',')
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .collect()
}

fn marker(
    lines: &[&str],
    index: usize,
    fixtures: &Path,
    patterns: &Patterns,
) -> Result<Option<(String, String)>> {
    let Some(previous) = lines[..index]
        .iter()
        .rev()
        .find(|line| !line.trim().is_empty())
    else {
        return Ok(None);
    };
    let Some(capture) = patterns.marker.captures(previous.trim()) else {
        return Ok(None);
    };
    let kind = capture
        .get(1)
        .ok_or_else(|| invalid("marker without expectation"))?
        .as_str();
    let reason = capture.get(2).map_or("", |value| value.as_str());
    let (expect, why) = if let Some(feature) = kind.strip_prefix("nightly") {
        let feature = feature.trim_matches(['(', ')']);
        let why = if reason.is_empty() && !feature.is_empty() {
            format!("requires nightly feature {feature}")
        } else {
            reason.to_owned()
        };
        ("nightly".to_owned(), why)
    } else if let Some(name) = kind
        .strip_prefix("fixture(")
        .and_then(|name| name.strip_suffix(')'))
    {
        let directory = fixtures.join(name);
        for required in ["Cargo.toml", "verify.sh"] {
            if !directory.join(required).is_file() {
                return Err(invalid(format!(
                    "fixture {name:?} before line {} has no {required}",
                    index + 1
                ))
                .into());
            }
        }
        let why = if reason.is_empty() {
            format!("verified by fixture {name}")
        } else {
            reason.to_owned()
        };
        (format!("fixture:{name}"), why)
    } else {
        (kind.to_owned(), reason.to_owned())
    };
    if matches!(expect.as_str(), "fragment" | "compile_fail" | "ignore") && why.is_empty() {
        return Err(invalid(format!(
            "explicit rust-check {expect:?} before line {} requires `; reason=...`",
            index + 1
        ))
        .into());
    }
    Ok(Some((
        expect,
        if why.is_empty() {
            "explicit expectation".into()
        } else {
            why
        },
    )))
}

fn native_expectation(
    attrs: &BTreeSet<&str>,
    file: &str,
    line: usize,
) -> Result<Option<(String, String)>> {
    if attrs.contains("compile_fail") && attrs.contains("ignore") {
        return Err(invalid(format!(
            "conflicting rustdoc fence attributes compile_fail+ignore in {file}:{line}"
        ))
        .into());
    }
    if attrs.contains("compile_fail") {
        Ok(Some((
            "compile_fail".into(),
            "native rustdoc `compile_fail` fence".into(),
        )))
    } else if attrs.contains("ignore") {
        Ok(Some((
            "ignore".into(),
            "native rustdoc `ignore` fence".into(),
        )))
    } else {
        Ok(None)
    }
}

fn expectation(
    lines: &[&str],
    index: usize,
    attrs: &BTreeSet<&str>,
    section: &str,
    file: &str,
    fixtures: &Path,
    patterns: &Patterns,
) -> Result<(String, String)> {
    let explicit = marker(lines, index, fixtures, patterns)?;
    let native = native_expectation(attrs, file, index + 1)?;
    if let (Some((given, _)), Some((rustdoc, _))) = (&explicit, &native)
        && given != rustdoc
    {
        return Err(invalid(format!(
            "conflicting rust-check {given:?} and rustdoc fence {rustdoc:?} in {file}:{}",
            index + 1
        ))
        .into());
    }
    if let Some(value) = explicit.or(native) {
        return Ok(value);
    }
    let normalized = section.trim().to_lowercase();
    if normalized.starts_with("good") {
        Ok(("compile".into(), "Good sections compile by default".into()))
    } else if normalized.starts_with("bad") {
        Ok(("compile".into(), "Bad sections compile by default".into()))
    } else {
        Ok(("auto".into(), "legacy classifier".into()))
    }
}

fn wrap(source: &str, patterns: &Patterns) -> String {
    let mut result = String::from(HEADER);
    if patterns.main.is_match(source) {
        result.push_str(source);
        result.push('\n');
    } else if source.contains("#![") || patterns.module.is_match(source) {
        result.push_str(source);
        result.push_str("\nfn main() {}\n");
    } else {
        result.push_str("async fn __ex() -> Result<(), Box<dyn std::error::Error>> {\n");
        result.push_str(source);
        result.push_str("\n;\nOk(())\n}\nfn main() {}\n");
    }
    result
}

fn parse_rule(
    filename: &str,
    text: &str,
    fixtures: &Path,
    patterns: &Patterns,
    output: &mut Outputs,
) -> Result<()> {
    // Python's original Path.read_text/splitlines applied universal newlines.
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let lines: Vec<&str> = normalized.lines().collect();
    let stem = filename
        .strip_suffix(".md")
        .ok_or_else(|| invalid("expected Markdown rule"))?;
    let stem = stem.replace('-', "_");
    let mut section = String::new();
    let mut index = 0;
    let mut file_index = 0;
    while index < lines.len() {
        let line = lines[index].trim();
        if let Some(heading) = patterns
            .heading
            .captures(lines[index])
            .and_then(|capture| capture.get(1))
        {
            heading.as_str().trim().clone_into(&mut section);
        }
        let Some(fence) = patterns.fence.captures(line) else {
            index += 1;
            continue;
        };
        let raw = fence.name("attrs").map_or("", |value| value.as_str());
        let attrs = attributes(raw);
        let start = index + 1;
        let mut end = start;
        while end < lines.len() && lines[end].trim() != "```" {
            end += 1;
        }
        let block = lines[start..end].join("\n");
        let (mut expect, reason) = expectation(
            &lines, index, &attrs, &section, filename, fixtures, patterns,
        )?;
        if block.contains("#![feature")
            && expect != "nightly"
            && expect != "compile_fail"
            && !expect.starts_with("fixture:")
        {
            return Err(invalid(format!(
                "{filename}:{}: nightly feature gate needs an explicit contract",
                start + 1
            ))
            .into());
        }
        let has_main = patterns.main.is_match(&block);
        let stable_run = expect == "run";
        if stable_run {
            if !has_main || attrs.contains("no_run") || attrs.contains("should_panic") {
                return Err(invalid(format!(
                    "{filename}:{}: run contract requires a runnable main",
                    start + 1
                ))
                .into());
            }
            "compile".clone_into(&mut expect);
        }
        let name = format!("{stem}__{file_index}");
        let generated =
            !matches!(expect.as_str(), "ignore" | "nightly") && !expect.starts_with("fixture:");
        let night_run = (expect == "nightly")
            .then_some(has_main && !attrs.contains("no_run") && !attrs.contains("should_panic"));
        let entry = Example {
            file: filename.to_owned(),
            line: start + 1,
            section: section.clone(),
            expect: expect.clone(),
            reason,
            generated,
            stable_run: stable_run.then_some(true),
            nightly_run: night_run,
        };
        if expect == "nightly" {
            output
                .nightly
                .push((format!("{name}.rs"), wrap(&block, patterns)));
        }
        if generated {
            output
                .stable
                .push((format!("{name}.rs"), wrap(&block, patterns)));
        }
        output.manifest.push((name, entry));
        file_index += 1;
        index = end + 1;
    }
    Ok(())
}

fn parse_all(rules: &Path, fixtures: &Path) -> Result<Outputs> {
    let patterns = Patterns::new()?;
    let mut files = fs::read_dir(rules)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    files.retain(|path| path.is_file() && path.extension().is_some_and(|ext| ext == "md"));
    files.sort();
    let mut output = Outputs::default();
    for file in files {
        let name = file
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| invalid(format!("invalid Markdown filename: {}", file.display())))?;
        parse_rule(
            name,
            &fs::read_to_string(&file)?,
            fixtures,
            &patterns,
            &mut output,
        )?;
    }
    Ok(output)
}

fn ascii_json(input: &str) -> Result<String> {
    let mut output = String::with_capacity(input.len());
    for character in input.chars() {
        if character.is_ascii() {
            output.push(character);
            continue;
        }
        let value = u32::from(character);
        if value < 0x10000 {
            write!(output, r"\u{value:04x}")?;
        } else {
            let offset = value - 0x10000;
            let high = 0xD800 + (offset >> 10);
            let low = 0xDC00 + (offset & 0x3FF);
            write!(output, r"\u{high:04x}\u{low:04x}")?;
        }
    }
    Ok(output)
}

fn write_sources(directory: &Path, files: &[(String, String)]) -> Result<()> {
    fs::create_dir_all(directory)?;
    for file in fs::read_dir(directory)? {
        let path = file?.path();
        if path.is_file() && path.extension().is_some_and(|extension| extension == "rs") {
            fs::remove_file(path)?;
        }
    }
    for (name, source) in files {
        fs::write(directory.join(name), source)?;
    }
    Ok(())
}

/// Generate all stable/nightly Cargo examples and exact expectation manifest.
///
/// # Errors
/// Returns an error for invalid Markdown or metadata, missing fixture verifiers,
/// non-UTF-8 input, or filesystem access failures.
pub fn generate(rules: &Path, fixtures: &Path, checks: &Path) -> Result<()> {
    // Validate the entire input corpus before altering existing generated files.
    let output = parse_all(rules, fixtures)?;
    write_sources(&checks.join("examples"), &output.stable)?;
    write_sources(&checks.join("nightly/examples"), &output.nightly)?;
    fs::create_dir_all(checks)?;
    let pretty = serde_json::to_string_pretty(&OrderedManifest(&output.manifest))?;
    fs::write(checks.join("manifest.json"), ascii_json(&pretty)?)?;
    println!(
        "generated {} example files (scanned {} rust blocks)",
        output.stable.len(),
        output.manifest.len()
    );
    let mut counts = BTreeMap::<&str, usize>::new();
    for (_, example) in &output.manifest {
        *counts.entry(&example.expect).or_default() += 1;
    }
    println!(
        "expectations: {}",
        counts
            .into_iter()
            .map(|(name, count)| format!("{name}={count}"))
            .collect::<Vec<_>>()
            .join(", ")
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = r#"# zz-verifier-metadata-fixture

> Temporary generator regression fixture

## Good compile fail

```rust,compile_fail
let _: u8 = "not a byte";
```

## Good ignore

```rust,ignore
this is intentionally not Rust;
```

## Good no run

```rust,no_run
fn compiles_but_is_not_run() {}
```

## Good should panic

```rust,should_panic
fn main() { panic!("runtime behavior is irrelevant to cargo check"); }
```

## Nightly executable

<!-- rust-check: nightly(iter_collect_into); reason=nightly API -->
```rust
#![feature(iter_collect_into)]
fn main() {}
```

## Nightly compile only

<!-- rust-check: nightly(iter_collect_into); reason=nightly API -->
```rust,no_run
#![feature(iter_collect_into)]
fn main() {}
```

## Stable executable

<!-- rust-check: run -->
```rust
fn main() {}
```

## Fixture backed

<!-- rust-check: fixture(feature-additive) -->
```rust
#![cfg_attr(not(feature = "std"), no_std)]
```
"#;

    fn fixture_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../fixtures")
    }

    #[test]
    fn rustdoc_markers_and_run_contracts() -> Result<()> {
        let mut output = Outputs::default();
        let patterns = Patterns::new()?;
        parse_rule(
            "zz_verifier_metadata_fixture.md",
            FIXTURE,
            &fixture_dir(),
            &patterns,
            &mut output,
        )?;
        let expected = [
            ("compile_fail", true, None, None),
            ("ignore", false, None, None),
            ("compile", true, None, None),
            ("compile", true, None, None),
            ("nightly", false, None, Some(true)),
            ("nightly", false, None, Some(false)),
            ("compile", true, Some(true), None),
            ("fixture:feature-additive", false, None, None),
        ];
        assert_eq!(output.manifest.len(), expected.len());
        for (index, ((name, actual), &(expect, generated, stable_run, nightly_run))) in
            output.manifest.iter().zip(&expected).enumerate()
        {
            assert_eq!(name, &format!("zz_verifier_metadata_fixture__{index}"));
            assert_eq!(actual.expect, expect);
            assert_eq!(actual.generated, generated);
            assert_eq!(actual.stable_run, stable_run);
            assert_eq!(actual.nightly_run, nightly_run);
        }
        assert_eq!(output.stable.len(), 4);
        assert_eq!(output.nightly.len(), 2);
        assert!(
            output
                .nightly
                .iter()
                .all(|(_, source)| source.contains("fn main()"))
        );
        Ok(())
    }

    #[test]
    fn incompatible_contracts_and_unknown_fixtures_are_rejected() -> Result<()> {
        let patterns = Patterns::new()?;
        let cases = [
            "## Good\n<!-- rust-check: run -->\n```rust,ignore\nfn main() {}\n```\n",
            "## Good\n<!-- rust-check: fragment -->\n```rust\nfn main() {}\n```\n",
            "## Good\n```rust\n#![feature(portable_simd)]\n```\n",
            "## Good\n<!-- rust-check: run -->\n```rust\nlet x=1;\n```\n",
            "## Good\n<!-- rust-check: fixture(unknown-verifier) -->\n```rust\nfn main() {}\n```\n",
            "## Good\n```rust,compile_fail,ignore\nfn main() {}\n```\n",
        ];
        for input in cases {
            let mut output = Outputs::default();
            assert!(parse_rule("test.md", input, &fixture_dir(), &patterns, &mut output).is_err());
        }
        Ok(())
    }

    #[test]
    fn universal_newlines_and_wrapper_shape() -> Result<()> {
        let patterns = Patterns::new()?;
        let mut output = Outputs::default();
        parse_rule(
            "own-test.md",
            "## Good\r\n```rust\r#[allow(dead_code)]\r\nfn main() {}\r```\r",
            &fixture_dir(),
            &patterns,
            &mut output,
        )?;
        assert_eq!(output.stable.len(), 1);
        assert_eq!(output.manifest[0].1.line, 3);
        assert!(output.stable[0].1.ends_with("fn main() {}\n"));
        Ok(())
    }

    #[test]
    fn ascii_manifest_encoding_preserves_non_bmp_values() -> Result<()> {
        let value = serde_json::to_string("é🦀")?;
        assert_eq!(ascii_json(&value)?, r#""\u00e9\ud83e\udd80""#);
        Ok(())
    }
}
