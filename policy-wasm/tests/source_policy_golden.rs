//! Frozen acceptance expectations captured from the original independent
//! Python reference before removal. The production implementation is Rust/WASI.
use regex::Regex;
use serde::Deserialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    error::Error,
    fs, io,
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Deserialize)]
struct Snapshot {
    schema: u64,
    toolchain: String,
    cases: BTreeMap<String, Case>,
}

#[derive(Deserialize)]
struct Case {
    status: i32,
    counts: Option<[usize; 3]>,
    violations: Vec<String>,
}

fn not_found(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::NotFound, message.into())
}

fn normalize_violations(output: &str, root: &Path) -> Vec<String> {
    let prefix = root.to_string_lossy().replace('\\', "/");
    let ordinary = prefix.strip_prefix("//?/").unwrap_or(&prefix);
    output
        .lines()
        .filter_map(|line| line.strip_prefix("  - "))
        .map(|line| {
            let normalized = line.replace('\\', "/");
            let relative = normalized
                .strip_prefix(&prefix)
                .or_else(|| normalized.strip_prefix(ordinary));
            relative.map_or_else(|| normalized.clone(), |tail| format!("<repo>{tail}"))
        })
        .collect()
}

#[test]
fn frozen_source_policy_fixture_contracts() -> Result<(), Box<dyn Error>> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let root = manifest
        .parent()
        .ok_or_else(|| not_found("policy crate is missing its repository root"))?
        .canonicalize()?;
    let fixture_dir = root.join("checks/fixtures");
    let module = manifest.join("module.json");
    let check = manifest.join("check.mjs");
    let snapshot: Snapshot =
        serde_json::from_slice(&fs::read(manifest.join("tests/golden/source-policy.json"))?)?;
    assert_eq!(snapshot.schema, 1);
    let compiler: toml::Value =
        toml::from_str(&fs::read_to_string(root.join("rust-toolchain.toml"))?)?;
    let toolchain = compiler
        .get("toolchain")
        .and_then(|table| table.get("channel"))
        .and_then(toml::Value::as_str)
        .ok_or_else(|| not_found("no pinned Rust compiler channel"))?;
    assert_eq!(
        snapshot.toolchain, toolchain,
        "review frozen policy expectations after compiler updates"
    );

    let mut names = BTreeSet::new();
    for item in fs::read_dir(&fixture_dir)? {
        let path = item?.path();
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if name.starts_with("strict-ci-") && path.join("Cargo.toml").is_file() {
            names.insert(name.to_owned());
        }
    }
    assert_eq!(
        names,
        snapshot.cases.keys().cloned().collect(),
        "every policy fixture requires explicit frozen expectations"
    );

    let summary = Regex::new(
        r"\((\d+) Rust files, (\d+) generated lint boundaries, (\d+) suppression attributes\)",
    )?;
    let mut disagreements = Vec::new();
    for (name, expected) in snapshot.cases {
        let output = Command::new("node")
            .arg(&check)
            .arg(&module)
            .arg(toolchain)
            .current_dir(fixture_dir.join(&name))
            .output()?;
        let status = output.status.code().ok_or_else(|| {
            not_found(format!(
                "{name}: source-policy terminated without an exit code"
            ))
        })?;
        let stdout = String::from_utf8(output.stdout)?;
        let stderr = String::from_utf8(output.stderr)?;
        if status != expected.status {
            disagreements.push(format!(
                "{name}: exit expected {}, got {status}: {stdout}\n{stderr}",
                expected.status
            ));
        }
        let counts = match summary.captures(&stdout) {
            Some(values) => Some([values[1].parse()?, values[2].parse()?, values[3].parse()?]),
            None => None,
        };
        if counts != expected.counts {
            disagreements.push(format!(
                "{name}: counts {counts:?}, expected {:?}",
                expected.counts
            ));
        }
        let violations = normalize_violations(&stderr, &root);
        if violations != expected.violations {
            disagreements.push(format!(
                "{name}: actual {violations:?} vs expected {:?}",
                expected.violations
            ));
        }
    }
    assert!(
        disagreements.is_empty(),
        "Policy snapshot disagreements:\n{}",
        disagreements.join("\n")
    );
    Ok(())
}

#[test]
fn violation_normalization_is_path_local() {
    let root = PathBuf::from("/tmp/checkout");
    let output = "header\n  - /tmp/checkout/file.rs:3: forbidden\n  - external error\n";
    assert_eq!(
        normalize_violations(output, &root),
        ["<repo>/file.rs:3: forbidden", "external error"]
    );
    let windows = PathBuf::from(r"\\?\C:\repository");
    let lines = "  - C:\\repository\\checks\\fixtures\\one\\src\\lib.rs:3: forbidden\n";
    assert_eq!(
        normalize_violations(lines, &windows),
        ["<repo>/checks/fixtures/one/src/lib.rs:3: forbidden"]
    );
}
