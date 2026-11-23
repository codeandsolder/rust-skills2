use super::{Result, invalid};
use regex::Regex;
use std::{collections::BTreeSet, fs, path::Path};

fn block_has(text: &str, header: &str, expected: &str) -> bool {
    let indent = header.len() - header.trim_start().len();
    let mut lines = text.lines();
    while let Some(line) = lines.next() {
        if line != header {
            continue;
        }
        for child in lines.by_ref() {
            if child.trim().is_empty() {
                continue;
            }
            if child.len() - child.trim_start().len() <= indent {
                break;
            }
            if child == expected {
                return true;
            }
        }
    }
    false
}

fn action_pins(root: &Path) -> Result<()> {
    let refs = Regex::new(r"\buses:\s*([^\s#]+)")?;
    let sha = Regex::new(r"^[a-f0-9]{40}$")?;
    for relative in [
        ".github/workflows/strict-rust.yml",
        ".github/actions/rust-strict/action.yml",
        ".github/actions/python-strict/action.yml",
        ".github/actions/source-lint-policy/action.yml",
    ] {
        let text = fs::read_to_string(root.join(relative))?;
        for (line, raw) in text.lines().enumerate() {
            let Some(reference) = refs.captures(raw).map(|item| item[1].to_owned()) else {
                continue;
            };
            if reference.starts_with("./") {
                continue;
            }
            let Some((_, version)) = reference.rsplit_once('@') else {
                return Err(invalid(format!(
                    "{relative}:{}: external action lacks an immutable ref: {reference}",
                    line + 1
                ))
                .into());
            };
            if !sha.is_match(version) {
                return Err(invalid(format!(
                    "{relative}:{}: external action ref is not a full commit SHA: {reference}",
                    line + 1
                ))
                .into());
            }
        }
    }
    Ok(())
}

fn workflow_shape(workflow: &str) -> Result<()> {
    let selector = r#"runs-on: ${{ github.event.repository.private && fromJSON('["self-hosted","Linux","X64","local-ci"]') || 'ubuntu-24.04' }}"#;
    if !workflow.contains(selector) {
        return Err(invalid("strict Rust visibility routing must use hosted Ubuntu for public and local Linux x64 for private").into());
    }
    for required in [
        "repository: ${{ job.workflow_repository }}",
        "ref: ${{ job.workflow_sha }}",
        "uses: ./.rust-skills2-gate/.github/actions/python-strict",
        "uses: ./.rust-skills2-gate/.github/actions/rust-strict",
        "sparse-checkout: |",
        "      /.github/actions/",
        "      /scripts/",
        "      /policy-wasm/check.mjs",
        "      /policy-wasm/run.mjs",
        "      /policy-wasm/module.mjs",
        "      /policy-wasm/module.json",
        "      /policy-wasm/module.wasm.gz",
        "sparse-checkout-cone-mode: false",
    ] {
        if !workflow.contains(required) {
            return Err(invalid(format!(
                "strict reusable workflow is missing immutable self-checkout contract: {required}"
            ))
            .into());
        }
    }
    if workflow.contains("codeandsolder/rust-skills2/.github/actions/") {
        return Err(invalid("strict reusable workflow must not call rust-skills2 composite actions through a remote ref").into());
    }
    Ok(())
}

fn provider_contract(workflow: &str) -> Result<()> {
    let mut providers = BTreeSet::new();
    for action in ["setup-sccache", "finalize-sccache"] {
        let pattern = Regex::new(&format!(
            r"(?m)^\s*uses:\s*codeandsolder/ci-workflows/\.github/actions/{action}@([0-9a-f]{{40}})\s*# main\s*$"
        ))?;
        let revisions = pattern
            .captures_iter(workflow)
            .map(|capture| capture[1].to_owned())
            .collect::<Vec<_>>();
        if revisions.len() != 1 {
            return Err(invalid(format!(
                "strict reusable workflow must use exactly one canonical {action}; found {}",
                revisions.len()
            ))
            .into());
        }
        providers.insert(revisions[0].clone());
    }
    if providers.len() != 1 {
        return Err(invalid(
            "strict reusable workflow setup/finalize actions must pin the same provider commit SHA",
        )
        .into());
    }
    for forbidden in [
        "Swatinem/rust-cache",
        "preserve-rustc-wrapper",
        "rustc-wrapper:",
        "sccache-server-port",
    ] {
        if workflow.contains(forbidden) {
            return Err(invalid(format!(
                "strict reusable workflow retains obsolete cache escape hatch: {forbidden}"
            ))
            .into());
        }
    }
    let quarantine = Regex::new(
        r"(?m)^        uses: codeandsolder/ci-workflows/\.github/actions/cargo-release-quarantine@([0-9a-f]{40}) # main$",
    )?;
    let revision = quarantine
        .captures(workflow)
        .ok_or_else(|| invalid("strict Rust must pin the shared Cargo quarantine action"))?[1]
        .to_owned();
    let start = workflow
        .find("      - name: Quarantine newly introduced crates.io versions")
        .ok_or_else(|| invalid("strict Rust has no Cargo quarantine step"))?;
    let after = &workflow[start..];
    let step = after
        .split_once("\n      - name:")
        .map_or(after, |(step, _)| step);
    if !step.contains("if: github.event_name == 'pull_request'\n")
        || step.contains("github.repository_owner")
    {
        return Err(invalid(
            "external crate quarantine must run on every PR regardless of caller ownership",
        )
        .into());
    }
    if !workflow.contains("base-ref: ${{ github.event.pull_request.base.sha }}") {
        return Err(invalid("Cargo quarantine must compare to the PR base").into());
    }
    if !workflow.contains("lockfile: auto") {
        return Err(invalid("Cargo quarantine must scan all tracked workspaces").into());
    }
    if !providers.contains(&revision) {
        return Err(
            invalid("Cargo quarantine and sccache must use one trusted CI provider SHA").into(),
        );
    }
    Ok(())
}

/// Enforce immutable action pins, trust-root consistency and reusable-gate contracts.
///
/// # Errors
/// Returns an error if an action pin, workflow selector or trust-root contract differs.
pub fn pins(root: &Path) -> Result<()> {
    action_pins(root)?;
    let workflow = fs::read_to_string(root.join(".github/workflows/strict-rust.yml"))?;
    workflow_shape(&workflow)?;
    provider_contract(&workflow)?;
    let python = fs::read_to_string(root.join(".github/actions/python-strict/action.yml"))?;
    if !block_has(&python, "  ban-python-outside-ci:", "    default: \"true\"") {
        return Err(invalid("strict Python composite must reject non-CI Python by default").into());
    }
    if !block_has(
        &workflow,
        "      ban-python-outside-ci:",
        "        default: true",
    ) {
        return Err(
            invalid("strict reusable workflow must reject non-CI Python by default").into(),
        );
    }
    println!(
        "rust-skills2: strict gate refs are immutable, self-checkout is pinned to job.workflow_sha, and non-CI Python is denied by default"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_field_does_not_match_sibling() {
        let text = "  a:\n    default: true\n  b:\n    default: false\n";
        assert!(block_has(text, "  a:", "    default: true"));
        assert!(!block_has(text, "  a:", "    default: false"));
    }
}
