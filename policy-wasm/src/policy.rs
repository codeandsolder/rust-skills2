use crate::Attribute;
use std::collections::{BTreeMap, BTreeSet};

const BLOCKED_GROUPS: [&str; 3] = ["clippy::correctness", "clippy::suspicious", "clippy::perf"];
const BLOCKED_LINTS: [&str; 16] = [
    "clippy::allow_attributes",
    "clippy::allow_attributes_without_reason",
    "clippy::await_holding_lock",
    "clippy::dbg_macro",
    "clippy::deprecated_attributes_without_note",
    "clippy::expect_used",
    "clippy::missing_safety_doc",
    "clippy::must_use_without_reason",
    "clippy::panic",
    "clippy::todo",
    "clippy::undocumented_unsafe_blocks",
    "clippy::unimplemented",
    "clippy::unwrap_used",
    "unexpected_cfgs",
    "unfulfilled_lint_expectations",
    "unsafe_op_in_unsafe_fn",
];

pub struct Policy {
    groups: BTreeSet<String>,
    blocked: BTreeMap<String, &'static str>,
}

impl Policy {
    /// Construct the policy from the exact compiler's help output, never a stale lint snapshot.
    pub fn from_clippy_help(help: &str) -> Result<Self, String> {
        let mut groups = BTreeMap::<String, Vec<String>>::new();
        let mut in_groups = false;
        for line in help.lines() {
            if line.starts_with("Lint groups provided by rustc:")
                || line.starts_with("Lint groups loaded by this crate:")
            {
                in_groups = true;
                continue;
            }
            if line.starts_with("Lint ") && line.ends_with(':') {
                in_groups = false;
                continue;
            }
            if !in_groups || !line.starts_with(char::is_whitespace) {
                continue;
            }
            let line = line.trim_start();
            let Some(end) = line.find(char::is_whitespace) else {
                continue;
            };
            let (name, rest) = line.split_at(end);
            if rest.len() - rest.trim_start().len() < 2
                || !name
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b':' | b'-'))
            {
                continue;
            }
            groups.insert(
                name.replace('-', "_"),
                rest.split(',')
                    .map(str::trim)
                    .filter(|word| !word.is_empty())
                    .map(|word| word.replace('-', "_"))
                    .collect(),
            );
        }

        let mut blocked = BTreeMap::new();
        for group in BLOCKED_GROUPS {
            let members = groups
                .get(group)
                .ok_or_else(|| format!("could not discover required Clippy group: {group}"))?;
            for member in members {
                if member != "clippy::large_enum_variant" {
                    blocked.entry(member.clone()).or_insert(group);
                }
            }
        }
        Ok(Self {
            groups: groups.into_keys().collect(),
            blocked,
        })
    }

    /// Append diagnostics for a single parsed lint attribute.
    pub fn inspect(&self, path: &str, attribute: &Attribute, violations: &mut Vec<String>) {
        let location = format!("{path}:{}", attribute.line);
        match attribute.kind.as_str() {
            "warn" => {
                violations.push(format!("{location}: #[warn(...)] is forbidden in handwritten source; it can lower the strict command-line lint level without suppressing a finding"));
                return;
            }
            "allow" => {
                violations.push(format!("{location}: #[allow(...)] is forbidden in handwritten source; use #[expect(lint, reason = \"...\")] or cfg_attr(..., expect(...)) for configuration-scoped exceptions"));
                return;
            }
            _ => {}
        }
        if attribute.lints.len() != 1 {
            violations.push(format!(
                "{location}: #[{}] must name exactly one lint; found {}",
                attribute.kind,
                attribute.lints.len()
            ));
        }
        if !attribute.has_reason {
            violations.push(format!(
                "{location}: #[{}] must include reason = \"...\"",
                attribute.kind
            ));
        }
        for lint in &attribute.lints {
            if self.groups.contains(lint) {
                violations.push(format!("{location}: {} of lint group {lint} is forbidden; name one specific suppressible lint instead", attribute.kind));
            } else if let Some(group) = self.blocked.get(lint) {
                violations.push(format!("{location}: {lint} belongs to {group} on this nightly; correctness/suspicious/perf suppressions are forbidden"));
            } else if BLOCKED_LINTS.contains(&lint.as_str()) {
                violations.push(format!(
                    "{location}: suppressing {lint} would weaken suppression policy"
                ));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lint_attributes;

    const HELP: &str = "Lint groups provided by rustc:\n    unused    unused-imports, unused-variables\nLint groups loaded by this crate:\n    clippy::correctness    clippy::foo\n    clippy::suspicious    clippy::bar\n    clippy::perf    clippy::large-enum-variant, clippy::baz\n";

    #[test]
    fn compiler_output_required() {
        assert!(Policy::from_clippy_help("").is_err());
        assert!(Policy::from_clippy_help(HELP).is_ok());
    }

    #[test]
    fn checks_groups_and_exception() -> Result<(), String> {
        let policy = Policy::from_clippy_help(HELP)?;
        let source = r#"#[expect(clippy::foo, reason = "test")]
#[expect(clippy::large_enum_variant, reason = "test")]
#[expect(unused, reason = "test")]
#[expect(clippy::panic, reason = "test")]
#[allow(unused)]
#[warn(unused)]
#[expect(clippy::pedantic, clippy::bar)]
"#;
        let mut violations = Vec::new();
        for attribute in lint_attributes(source) {
            policy.inspect("src/lib.rs", &attribute, &mut violations);
        }
        assert_eq!(violations.len(), 8);
        assert!(violations[0].contains("clippy::correctness"));
        assert!(violations[1].contains("lint group unused"));
        assert!(violations[2].contains("would weaken suppression policy"));
        assert!(violations[3].contains("#[allow"));
        assert!(violations[4].contains("#[warn"));
        assert!(violations[5].contains("exactly one"));
        assert!(violations[6].contains("must include reason"));
        assert!(violations[7].contains("clippy::suspicious"));
        Ok(())
    }
}
