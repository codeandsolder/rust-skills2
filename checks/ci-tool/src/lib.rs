//! Rule-library CI checks with explicit, testable inputs and no Python runtime.
pub mod generator;
pub mod pins;
use regex::Regex;
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    error::Error,
    fs, io,
    path::Path,
};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}

fn rules(root: &Path) -> Result<BTreeMap<String, String>> {
    let mut files = BTreeMap::new();
    for entry in fs::read_dir(root.join("rules"))? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().is_some_and(|ext| ext == "md") && path.is_file() {
            let name = path
                .file_stem()
                .and_then(|name| name.to_str())
                .ok_or_else(|| invalid(format!("invalid rule filename: {}", path.display())))?;
            if !name
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
            {
                return Err(invalid(format!("invalid rule identifier: {name}")).into());
            }
            files.insert(name.to_owned(), fs::read_to_string(&path)?);
        }
    }
    if files.is_empty() {
        return Err(invalid("rules directory contains no Markdown rule files").into());
    }
    Ok(files)
}

fn validate_rules(files: &BTreeMap<String, String>, skill: &str) -> Result<Vec<String>> {
    let links = Regex::new(r"\]\((?:\./)?([a-z0-9-]+\.md)\)")?;
    let indexed = Regex::new(r"rules/([a-z0-9-]+\.md)")?;
    let file_names: BTreeSet<_> = files.keys().map(|name| format!("{name}.md")).collect();
    let mut errors = Vec::new();

    for (name, text) in files {
        let filename = format!("{name}.md");
        let first = text.lines().next().unwrap_or("").trim();
        if first != format!("# {name}") {
            errors.push(format!(
                "{filename}: first line is {first:?}, expected '# {name}'"
            ));
        }
        if !text.lines().take(6).any(|line| line.starts_with("> ")) {
            errors.push(format!(
                "{filename}: missing '> ' summary line near the top"
            ));
        }
        for section in ["## Why It Matters", "## See Also"] {
            if !text.contains(section) {
                errors.push(format!("{filename}: missing '{section}' section"));
            }
        }
        for link in links.captures_iter(text) {
            let target = &link[1];
            if !file_names.contains(target) {
                errors.push(format!("{filename}: broken link -> {target}"));
            }
        }
    }

    let linked: BTreeSet<_> = indexed
        .captures_iter(skill)
        .map(|capture| capture[1].to_owned())
        .collect();
    for name in linked.difference(&file_names) {
        errors.push(format!("SKILL.md: links missing file rules/{name}"));
    }
    for name in file_names.difference(&linked) {
        errors.push(format!(
            "SKILL.md: rule rules/{name} is not listed in the index"
        ));
    }
    Ok(errors)
}

/// Check the rule headings, linked references and exact index inventory.
///
/// # Errors
/// Returns an error for malformed documentation, missing files or broken links.
pub fn validate(root: &Path) -> Result<()> {
    let files = rules(root)?;
    let skill = fs::read_to_string(root.join("SKILL.md"))?;
    let errors = validate_rules(&files, &skill)?;
    if !errors.is_empty() {
        return Err(invalid(format!(
            "VALIDATION FAILED ({} problem(s)):\n{}",
            errors.len(),
            errors
                .iter()
                .map(|message| format!("  - {message}"))
                .collect::<Vec<_>>()
                .join("\n")
        ))
        .into());
    }
    println!(
        "OK: {} rules valid; index lists all {} of them.",
        files.len(),
        files.len()
    );
    Ok(())
}

const CATEGORIES: [(&str, &str, &str); 26] = [
    ("own-", "Ownership & Borrowing", "CRITICAL"),
    ("err-", "Error Handling", "CRITICAL"),
    ("mem-", "Memory Optimization", "CRITICAL"),
    ("unsafe-", "Unsafe Code", "CRITICAL"),
    ("api-", "API Design", "HIGH"),
    ("async-", "Async/Await", "HIGH"),
    ("conc-", "Concurrency", "HIGH"),
    ("opt-", "Compiler Optimization", "HIGH"),
    ("num-", "Numeric & Arithmetic Safety", "HIGH"),
    ("type-", "Type Safety", "MEDIUM"),
    ("trait-", "Trait & Generics Design", "MEDIUM"),
    ("conv-", "Conversions", "MEDIUM"),
    ("const-", "Const & Compile-Time", "MEDIUM"),
    ("serde-", "Serde", "MEDIUM"),
    ("pat-", "Pattern Matching", "MEDIUM"),
    ("macro-", "Macros", "MEDIUM"),
    ("closure-", "Closures", "MEDIUM"),
    ("coll-", "Collections", "MEDIUM"),
    ("name-", "Naming Conventions", "MEDIUM"),
    ("test-", "Testing", "MEDIUM"),
    ("doc-", "Documentation", "MEDIUM"),
    ("obs-", "Observability", "MEDIUM"),
    ("perf-", "Performance Patterns", "MEDIUM"),
    ("proj-", "Project Structure", "LOW"),
    ("lint-", "Clippy & Linting", "LOW"),
    ("anti-", "Anti-patterns", "REFERENCE"),
];

fn section(text: &str, first: &str, last: &str, replacement: &str) -> Result<String> {
    let start = text
        .find(first)
        .ok_or_else(|| invalid(format!("missing document anchor: {first}")))?;
    let after = start + first.len();
    let end = text[after..]
        .find(last)
        .ok_or_else(|| invalid(format!("missing document anchor: {last}")))?
        + after;
    Ok(format!("{}{replacement}{}", &text[..after], &text[end..]))
}

fn replace_count(text: &str, pattern: &str, replacement: &str) -> Result<String> {
    Ok(Regex::new(pattern)?
        .replace_all(text, regex::NoExpand(replacement))
        .into_owned())
}

fn summary(name: &str, text: &str) -> Result<String> {
    text.lines()
        .find_map(|line| line.strip_prefix("> ").map(str::trim))
        .map(str::to_owned)
        .ok_or_else(|| invalid(format!("{name}.md: no '> summary' line")).into())
}

fn render_readme(readme: &str, total: usize) -> Result<String> {
    let mut readme_new = readme.to_owned();
    for (pattern, replace) in [
        (r"rules-\d+", format!("rules-{total}")),
        (
            r"categories-\d+",
            format!("categories-{}", CATEGORIES.len()),
        ),
        (r"\d+ Rust rules", format!("{total} Rust rules")),
        (
            r"\d+ rules split into \d+ categories",
            format!("{total} rules split into {} categories", CATEGORIES.len()),
        ),
    ] {
        readme_new = replace_count(&readme_new, pattern, &replace)?;
    }
    Ok(readme_new)
}

fn render_index(
    files: &BTreeMap<String, String>,
    skill: &str,
    readme: &str,
) -> Result<(String, String)> {
    let names = files.keys().cloned().collect::<BTreeSet<_>>();
    let prefixes: BTreeSet<_> = CATEGORIES.iter().map(|category| category.0).collect();
    let unknown: Vec<_> = names
        .iter()
        .filter_map(|name| {
            name.split_once('-')
                .map_or(Some(name.as_str()), |(prefix, _)| {
                    (!prefixes.contains(format!("{prefix}-").as_str())).then_some(name.as_str())
                })
        })
        .collect();
    if !unknown.is_empty() {
        return Err(invalid(format!(
            "rules with unknown prefix (add to CATEGORIES): {unknown:?}"
        ))
        .into());
    }

    let link = Regex::new(r"rules/([a-z0-9-]+)\.md")?;
    let mut existing = Vec::new();
    let mut seen = BTreeSet::new();
    for capture in link.captures_iter(skill) {
        let name = capture[1].to_owned();
        if seen.insert(name.clone()) {
            existing.push(name);
        }
    }

    let mut rows = Vec::new();
    let mut sections = Vec::new();
    let mut total = 0;
    for (index, &(prefix, title, impact)) in CATEGORIES.iter().enumerate() {
        let group: BTreeSet<_> = names
            .iter()
            .filter(|name| name.starts_with(prefix))
            .cloned()
            .collect();
        let mut ordered: Vec<_> = existing
            .iter()
            .filter(|name| group.contains(*name))
            .cloned()
            .collect();
        ordered.extend(group.difference(&seen).cloned());
        total += ordered.len();
        rows.push(format!(
            "| {} | {title} | {impact} | `{prefix}` | {} |",
            index + 1,
            ordered.len()
        ));
        let mut lines = vec![
            format!("### {}. {title} ({impact})", index + 1),
            String::new(),
        ];
        for name in &ordered {
            let text = files
                .get(name)
                .ok_or_else(|| invalid(format!("missing {name}")))?;
            lines.push(format!(
                "- [`{name}`](rules/{name}.md) - {}",
                summary(name, text)?
            ));
        }
        sections.push(lines.join("\n"));
    }

    let table = format!(
        "| Priority | Category | Impact | Prefix | Rules |\n\
         |----------|----------|--------|--------|-------|\n{}",
        rows.join("\n")
    );
    let quickref = sections.join("\n\n");
    let revised = section(
        skill,
        "## Rule Categories by Priority\n\n",
        "\n\n---\n\n## Quick Reference",
        &table,
    )?;
    let revised = section(
        &revised,
        "## Quick Reference\n\n",
        "\n\n---\n\n## Recommended Cargo.toml Settings",
        &quickref,
    )?;
    let revised = replace_count(
        &revised,
        r"\d+ rules across \d+ categories",
        &format!("{total} rules across {} categories", CATEGORIES.len()),
    )?;

    Ok((revised, render_readme(readme, total)?))
}

/// Rebuild the human-readable rule index. Check mode never modifies files.
///
/// # Errors
/// Returns an error for malformed rule metadata, missing files or stale indexes.
pub fn index(root: &Path, check: bool) -> Result<()> {
    let files = rules(root)?;
    let skill_path = root.join("SKILL.md");
    let readme_path = root.join("README.md");
    let current_skill = fs::read_to_string(&skill_path)?;
    let current_readme = fs::read_to_string(&readme_path)?;
    let (new_skill, new_readme) = render_index(&files, &current_skill, &current_readme)?;
    if check {
        let mut stale = Vec::new();
        if current_skill != new_skill {
            stale.push("SKILL.md");
        }
        if current_readme != new_readme {
            stale.push("README.md");
        }
        if !stale.is_empty() {
            return Err(invalid(format!(
                "OUT OF DATE: {} — run rust-skills-ci ROOT index",
                stale.join(", ")
            ))
            .into());
        }
        println!(
            "OK: index up to date ({} rules, {} categories)",
            files.len(),
            CATEGORIES.len()
        );
    } else {
        if current_skill != new_skill {
            fs::write(&skill_path, new_skill)?;
        }
        if current_readme != new_readme {
            fs::write(&readme_path, new_readme)?;
        }
        println!(
            "wrote index: {} rules across {} categories",
            files.len(),
            CATEGORIES.len()
        );
    }
    Ok(())
}

/// Disallow weak acceptance classifications while retaining explicit fixture contracts.
///
/// # Errors
/// Returns an error for invalid JSON or unsupported weak expectations.
pub fn inventory(root: &Path) -> Result<()> {
    let manifest: Value = serde_json::from_slice(&fs::read(root.join("checks/manifest.json"))?)?;
    let entries = manifest
        .as_object()
        .ok_or_else(|| invalid("manifest is not a JSON object"))?;
    let mut forbidden = Vec::new();
    let mut fixtures = BTreeSet::new();
    for (name, info) in entries {
        let expectation = info
            .get("expect")
            .and_then(Value::as_str)
            .ok_or_else(|| invalid(format!("{name}: missing string expectation")))?;
        if expectation == "ignore" || expectation == "fragment" {
            let file = info.get("file").and_then(Value::as_str).unwrap_or("?");
            let line = info.get("line").and_then(Value::as_i64).unwrap_or(0);
            let section = info.get("section").and_then(Value::as_str).unwrap_or("?");
            forbidden.push((
                file.to_owned(),
                line,
                section.to_owned(),
                expectation.to_owned(),
            ));
        } else if let Some(name) = expectation.strip_prefix("fixture:") {
            fixtures.insert(name.to_owned());
        }
    }
    if !forbidden.is_empty() {
        forbidden.sort();
        let details: Vec<_> = forbidden
            .iter()
            .map(|(file, line, section, expectation)| {
                format!("  {file}:{line} [{section}] -> {expectation}")
            })
            .collect();
        return Err(invalid(format!(
            "FAIL: {} weak verifier exemption(s) remain:\n{}",
            forbidden.len(),
            details.join("\n")
        ))
        .into());
    }
    println!(
        "OK: no ignore/fragment contracts; {} referenced fixture contract(s)",
        fixtures.len()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn structural_validation_rejects_missing_rules_and_broken_links() -> Result<()> {
        let mut docs = BTreeMap::new();
        docs.insert(
            "own-good".to_owned(),
            "# own-good\n\n> A contract.\n## Why It Matters\ntext [other](missing.md)\n## See Also"
                .to_owned(),
        );
        let problems = validate_rules(&docs, "rules/own-absent.md")?;
        assert!(
            problems
                .iter()
                .any(|problem| problem.contains("broken link"))
        );
        assert!(
            problems
                .iter()
                .any(|problem| problem.contains("missing file"))
        );
        assert!(
            problems
                .iter()
                .any(|problem| problem.contains("not listed"))
        );
        Ok(())
    }

    #[test]
    fn index_requires_anchors_and_rejects_unknown_prefix() {
        let mut docs = BTreeMap::new();
        docs.insert(
            "unknown-contract".to_owned(),
            "# unknown-contract\n> Summary".to_owned(),
        );
        assert!(render_index(&docs, "", "").is_err());
        docs.clear();
        docs.insert(
            "own-contract".to_owned(),
            "# own-contract\n> Summary".to_owned(),
        );
        assert!(render_index(&docs, "", "").is_err());
    }

    #[test]
    fn ordered_index_remains_stable() -> Result<()> {
        let mut docs = BTreeMap::new();
        docs.insert("own-b".into(), "# own-b\n> B summary".into());
        docs.insert("own-a".into(), "# own-a\n> A summary".into());
        let skill = "## Rule Categories by Priority\n\nprevious\n\n---\n\n## Quick Reference\n\n- [`own-b`](rules/own-b.md)\n- [`own-a`](rules/own-a.md)\n\n---\n\n## Recommended Cargo.toml Settings";
        let (result, _) = render_index(&docs, skill, "")?;
        let b = result
            .find("- [`own-b`]")
            .ok_or_else(|| invalid("missing rule"))?;
        let a = result
            .find("- [`own-a`]")
            .ok_or_else(|| invalid("missing rule"))?;
        assert!(b < a, "must preserve existing human-curated order");
        Ok(())
    }
    #[test]
    fn repository_rule_documents_are_current() -> Result<()> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        validate(&root)?;
        index(&root, true)
    }

    #[test]
    fn repository_shared_action_pins_are_current() -> Result<()> {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        crate::pins::pins(&root)
    }
}
