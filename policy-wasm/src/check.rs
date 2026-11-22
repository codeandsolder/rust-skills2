use crate::{ATTRIBUTE, lint_attributes, mask_noncode, matching, policy::Policy};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs, io,
    path::{Path, PathBuf},
};

#[derive(Deserialize)]
pub struct Input {
    paths: Vec<PathBuf>,
    clippy_help: String,
    workspace_manifest: PathBuf,
    packages: Vec<Package>,
    rustflags: BTreeMap<String, String>,
    cargo_config: Value,
}

#[derive(Deserialize)]
struct Package {
    manifest: PathBuf,
    metadata: Value,
    targets: Vec<PathBuf>,
    candidates: BTreeMap<String, Candidate>,
}

#[derive(Deserialize)]
struct Candidate {
    absolute: bool,
    exists: bool,
    path: Option<PathBuf>,
}

#[derive(Serialize)]
pub struct Report {
    pub files: usize,
    pub boundaries: usize,
    pub suppression_attributes: usize,
    pub violations: Vec<String>,
}

fn lint_level(value: &toml::Value) -> Option<&str> {
    value
        .as_str()
        .or_else(|| value.get("level").and_then(toml::Value::as_str))
}

fn check_manifest(
    path: &Path,
    violations: &mut Vec<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let source = fs::read_to_string(path)?;
    let data: toml::Value = toml::from_str(&source)?;
    for (prefix, table) in [
        ("lints", data.get("lints")),
        (
            "workspace.lints",
            data.get("workspace").and_then(|w| w.get("lints")),
        ),
    ] {
        let Some(table) = table.and_then(toml::Value::as_table) else {
            continue;
        };
        for (tool, entries) in table {
            if tool == "workspace" {
                continue;
            }
            let Some(entries) = entries.as_table() else {
                continue;
            };
            for (lint, value) in entries {
                if lint_level(value) == Some("allow") {
                    violations.push(format!("{}: [{prefix}.{tool}] {lint} = allow is forbidden; keep the lint enabled and use a narrow reasoned #[expect(...)] at the source site", path.display()));
                }
            }
        }
    }
    Ok(())
}

fn rustflag_tokens(value: &str) -> Vec<String> {
    let normalized = value.replace('\x1f', " ");
    shlex::split(&normalized)
        .unwrap_or_else(|| normalized.split_whitespace().map(str::to_owned).collect())
}

fn allow_flags(tokens: &[String]) -> Vec<String> {
    let mut found = Vec::new();
    let mut tokens = tokens.iter();
    while let Some(token) = tokens.next() {
        if matches!(token.as_str(), "-A" | "--allow") {
            let target = tokens.next().map_or("<missing>", String::as_str);
            found.push(format!("{token} {target}"));
        } else if (token.starts_with("-A") && token.len() > 2) || token.starts_with("--allow=") {
            found.push(token.clone());
        }
    }
    found
}

fn flag_override(value: &str) -> bool {
    value.contains("--cap-lints") || value.contains("--force-warn")
}

fn check_config_value(key: &str, flags: &Value, violations: &mut Vec<String>) {
    let (override_level, tokens) = match flags {
        Value::String(value) => (flag_override(value), rustflag_tokens(value)),
        Value::Array(values) => {
            let values: Vec<_> = values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect();
            (values.iter().any(|value| flag_override(value)), values)
        }
        _ => {
            violations.push(format!("Cargo config {key} contains invalid rustflags"));
            return;
        }
    };
    if override_level {
        violations.push(format!(
            "Cargo config {key} contains a lint-level override (--cap-lints/--force-warn)"
        ));
    }
    if !allow_flags(&tokens).is_empty()
        || tokens
            .iter()
            .any(|token| !allow_flags(&rustflag_tokens(token)).is_empty())
    {
        violations.push(format!("Cargo config {key} contains a forbidden -A/--allow lint override; use a narrow reasoned #[expect(...)] in handwritten source instead"));
    }
}

fn check_flags(input: &Input, violations: &mut Vec<String>) {
    for (name, value) in &input.rustflags {
        if flag_override(value) {
            violations.push(format!(
                "environment {name} contains a lint-level override (--cap-lints/--force-warn)"
            ));
        }
        for flag in allow_flags(&rustflag_tokens(value)) {
            violations.push(format!("environment {name} contains forbidden lint allow flag {flag}; use a narrow reasoned #[expect(...)] in handwritten source instead"));
        }
    }
    if let Some(flags) = input
        .cargo_config
        .get("build")
        .and_then(|build| build.get("rustflags"))
    {
        check_config_value("build.rustflags", flags, violations);
    }
    if let Some(targets) = input.cargo_config.get("target").and_then(Value::as_object) {
        for (name, target) in targets {
            if let Some(flags) = target.get("rustflags") {
                check_config_value(&format!("target.{name}.rustflags"), flags, violations);
            }
        }
    }
}

fn generated_marker(path: &Path) -> bool {
    let Ok(text) = fs::read_to_string(path) else {
        return false;
    };
    let prefix = text.chars().take(4096).collect::<String>().to_lowercase();
    prefix.contains("@generated")
        || prefix.contains("automatically generated")
        || prefix.contains("auto-generated")
        || prefix.contains("generated by")
        || (prefix.contains("generated") && prefix.contains("do not edit"))
}

struct WrapperPatterns {
    literal: Regex,
    masked: Regex,
}

impl WrapperPatterns {
    fn new() -> Result<Self, regex::Error> {
        Ok(Self {
            literal: Regex::new(r#"include!\s*\(\s*"([^"]+)"\s*\)\s*;"#)?,
            masked: Regex::new(r"^include!\s*\(\s*\)\s*;$")?,
        })
    }

    fn is_wrapper(&self, path: &Path) -> bool {
        let Ok(text) = fs::read_to_string(path) else {
            return false;
        };
        let Some(parent) = path.parent() else {
            return false;
        };
        let masked = mask_noncode(&text);
        let mut body = masked.as_bytes().to_vec();

        for attribute in ATTRIBUTE.find_iter(&masked) {
            let Some(end) = matching(masked.as_bytes(), attribute.end() - 1, b'[', b']') else {
                return false;
            };
            body[attribute.start()..=end].fill(b' ');
        }

        let mut proven = 0;
        for include in self.literal.captures_iter(&text) {
            let (Some(full), Some(relative)) = (include.get(0), include.get(1)) else {
                continue;
            };
            if !self.masked.is_match(&masked[full.range()]) {
                continue;
            }
            let included = parent.join(relative.as_str());
            if !included.is_file() || !generated_marker(&included) {
                return false;
            }
            body[full.range()].fill(b' ');
            proven += 1;
        }
        proven > 0 && body.iter().all(u8::is_ascii_whitespace)
    }
}

fn boundary_error(package: &Package, message: &str, violations: &mut Vec<String>) {
    violations.push(format!("{}: {message}", package.manifest.display()));
}

fn package_boundaries(
    package: &Package,
    patterns: &WrapperPatterns,
    boundaries: &mut BTreeSet<PathBuf>,
    violations: &mut Vec<String>,
) {
    let Some(metadata) = package.metadata.get("rust-skills2") else {
        return;
    };
    if metadata.is_null() {
        return;
    }
    let Some(metadata) = metadata.as_object() else {
        boundary_error(
            package,
            "package.metadata.rust-skills2 must be a table",
            violations,
        );
        return;
    };
    let Some(declared) = metadata.get("generated-lint-boundaries") else {
        return;
    };
    let Some(paths) = declared
        .as_array()
        .filter(|paths| paths.iter().all(Value::is_string))
    else {
        boundary_error(
            package,
            "package.metadata.rust-skills2.generated-lint-boundaries must be an array of paths",
            violations,
        );
        return;
    };
    let Some(root) = package.manifest.parent() else {
        boundary_error(package, "manifest has no parent", violations);
        return;
    };
    for relative in paths.iter().filter_map(Value::as_str) {
        let Some(candidate) = package.candidates.get(relative) else {
            boundary_error(
                package,
                &format!("generated boundary path was not resolved by host: {relative}"),
                violations,
            );
            continue;
        };
        let error = if candidate.absolute {
            "generated lint boundary must be relative"
        } else if !candidate.exists {
            "generated lint boundary does not exist"
        } else if let Some(path) = &candidate.path {
            if !path.starts_with(root) {
                "generated lint boundary escapes package root"
            } else if path.extension().and_then(|ext| ext.to_str()) != Some("rs") {
                "generated lint boundary must name one .rs file"
            } else if package.targets.contains(path) {
                "generated lint boundary may not be a Cargo target entrypoint"
            } else if !generated_marker(path) && !patterns.is_wrapper(path) {
                "generated lint boundary must either identify generated provenance near the top or be a pure include! wrapper around marked generated Rust"
            } else {
                boundaries.insert(path.clone());
                continue;
            }
        } else {
            "generated lint boundary escapes package root"
        };
        boundary_error(package, &format!("{error}: {relative}"), violations);
    }
}

/// Inspect an explicit host snapshot. All policy decisions occur in this module.
///
/// # Errors
/// Returns an error if the compiler output is incomplete or a source file cannot be read.
pub fn check(input: Input) -> Result<Report, Box<dyn std::error::Error>> {
    let policy = Policy::from_clippy_help(&input.clippy_help)?;
    let patterns = WrapperPatterns::new()?;
    let mut report = Report {
        files: input.paths.len(),
        boundaries: 0,
        suppression_attributes: 0,
        violations: Vec::new(),
    };
    check_flags(&input, &mut report.violations);
    let mut manifests = input
        .packages
        .iter()
        .map(|p| &p.manifest)
        .collect::<BTreeSet<_>>();
    manifests.insert(&input.workspace_manifest);
    for manifest in manifests {
        if let Err(error) = check_manifest(manifest, &mut report.violations) {
            report.violations.push(format!(
                "{}: cannot inspect Cargo lint policy: {error}",
                manifest.display()
            ));
        }
    }
    let mut boundaries = BTreeSet::new();
    for package in &input.packages {
        package_boundaries(package, &patterns, &mut boundaries, &mut report.violations);
    }
    report.boundaries = boundaries.len();
    for path in input.paths {
        if boundaries.contains(&path) {
            continue;
        }
        let source = match fs::read_to_string(&path) {
            Ok(source) => source,
            Err(error) if error.kind() == io::ErrorKind::InvalidData => {
                report.violations.push(format!(
                    "{}: non-UTF-8 Rust source cannot be policy-checked",
                    path.display()
                ));
                continue;
            }
            Err(error) => return Err(format!("{}: {error}", path.display()).into()),
        };
        for attribute in lint_attributes(&source) {
            if attribute.kind != "warn" {
                report.suppression_attributes += 1;
            }
            policy.inspect(&path.to_string_lossy(), &attribute, &mut report.violations);
        }
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags() {
        for (value, expected) in [
            ("-C opt-level=3 -A dead_code", "-A dead_code"),
            ("-Aclippy::pedantic", "-Aclippy::pedantic"),
            ("--allow=unused_imports", "--allow=unused_imports"),
            ("-Copt-level=3\x1f--allow\x1fdead_code", "--allow dead_code"),
        ] {
            assert_eq!(allow_flags(&rustflag_tokens(value)), [expected]);
        }
        assert_eq!(
            allow_flags(&rustflag_tokens("-D warnings -C target-cpu=x86-64-v2")),
            Vec::<String>::new()
        );
    }

    #[test]
    fn manifest_level() -> Result<(), toml::de::Error> {
        let data: toml::Value = toml::from_str(
            r#"[workspace.lints.clippy]
missing_errors_doc = "allow"
too_many_lines = { level = "deny", priority = 0 }
"#,
        )?;
        let lints = &data["workspace"]["lints"]["clippy"];
        assert_eq!(lint_level(&lints["missing_errors_doc"]), Some("allow"));
        assert_eq!(lint_level(&lints["too_many_lines"]), Some("deny"));
        Ok(())
    }
}
