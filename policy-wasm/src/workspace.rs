//! Resolve the selected workspace members and their effective test-panic policy.

use crate::check::Package;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeSet;

#[derive(Deserialize)]
pub struct Request {
    pub default_allow_test_panics: bool,
    pub cargo_args: Vec<String>,
    pub default_members: Vec<String>,
    pub metadata: Value,
}

#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
enum Policy {
    Strict,
    Relaxed,
}

#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct Row {
    policy: Policy,
    spec: String,
}

#[derive(Default)]
struct Selectors<'a> {
    workspace: bool,
    packages: Vec<&'a str>,
    excludes: Vec<&'a str>,
}

impl<'a> Selectors<'a> {
    fn parse(args: &'a [String]) -> Result<Self, String> {
        let mut selectors = Self::default();
        let mut args = args.iter().map(String::as_str);
        while let Some(arg) = args.next() {
            match arg {
                "--workspace" => selectors.workspace = true,
                "-p" | "--package" | "--exclude" => {
                    let value = args
                        .next()
                        .ok_or_else(|| format!("missing value for {arg}"))?;
                    if arg == "--exclude" {
                        selectors.excludes.push(value);
                    } else {
                        selectors.packages.push(value);
                    }
                }
                // Consume non-package selector values as a pair, not as flags.
                "-F" | "--features" | "--target" | "--bin" | "--example" | "--test" | "--bench" => {
                    args.next()
                        .ok_or_else(|| format!("missing value for {arg}"))?;
                }
                _ => {
                    if let Some(value) = arg.strip_prefix("--package=") {
                        selectors.packages.push(value);
                    } else if let Some(value) = arg.strip_prefix("--exclude=") {
                        selectors.excludes.push(value);
                    }
                }
            }
        }
        if !selectors.workspace && !selectors.excludes.is_empty() {
            return Err("--exclude can only be used together with --workspace".into());
        }
        Ok(selectors)
    }
}

fn matches(package: &Package, spec: &str) -> bool {
    spec == package.name
        || spec == package.id
        || spec
            .split_once('@')
            .is_some_and(|(name, version)| name == package.name && version == package.version)
}

fn select<'a>(packages: &'a [Package], request: &Request) -> Result<Vec<&'a Package>, String> {
    let selectors = Selectors::parse(&request.cargo_args)?;
    let mut explicit = BTreeSet::new();
    for spec in selectors.packages {
        let candidates: Vec<_> = packages
            .iter()
            .filter(|member| matches(member, spec))
            .collect();
        let [member] = candidates.as_slice() else {
            return Err(format!(
                "package selector {spec:?} resolved to {} workspace members; use an exact name@version spec",
                candidates.len()
            ));
        };
        explicit.insert(member.id.as_str());
    }
    let defaults: BTreeSet<_> = request.default_members.iter().map(String::as_str).collect();
    let use_defaults = explicit.is_empty()
        && !defaults.is_empty()
        && packages
            .iter()
            .any(|package| defaults.contains(package.id.as_str()));
    // Cargo's --workspace takes precedence over explicit -p selections, but
    // it still validates their names. Exclusions apply to the entire workspace.
    let mut selected: Vec<_> = packages
        .iter()
        .filter(|package| {
            selectors.workspace
                || if explicit.is_empty() {
                    !use_defaults || defaults.contains(package.id.as_str())
                } else {
                    explicit.contains(package.id.as_str())
                }
        })
        .collect();
    for spec in selectors.excludes {
        if !selected.iter().any(|member| matches(member, spec)) {
            return Err(format!(
                "exclude selector {spec:?} does not match a selected workspace member"
            ));
        }
        selected.retain(|member| !matches(member, spec));
    }
    if selected.is_empty() {
        return Err("Cargo selectors resolved to no workspace packages".into());
    }
    selected.sort_unstable_by(|left, right| {
        (&left.name, &left.version).cmp(&(&right.name, &right.version))
    });
    Ok(selected)
}

fn table<'a>(
    metadata: &'a Value,
    location: &str,
) -> Result<Option<&'a Map<String, Value>>, String> {
    match metadata {
        Value::Null => Ok(None),
        Value::Object(map) => match map.get("rust-skills2") {
            None | Some(Value::Null) => Ok(None),
            Some(Value::Object(policy)) => Ok(Some(policy)),
            _ => Err(format!("{location} rust-skills2 metadata must be a table")),
        },
        _ => Err(format!("{location} metadata must be a table")),
    }
}

fn effective(metadata: &Value, inherited: bool, location: &str) -> Result<bool, String> {
    let Some(fields) = table(metadata, location)? else {
        return Ok(inherited);
    };
    let location = format!("{location}.rust-skills2");
    let override_value = fields
        .get("allow-test-panics")
        .map(|value| {
            value
                .as_bool()
                .ok_or_else(|| format!("{location} allow-test-panics must be true or false"))
        })
        .transpose()?;
    let reason = fields
        .get("allow-test-panics-reason")
        .map(|value| {
            value
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| {
                    format!("{location} allow-test-panics-reason must be a non-empty string")
                })
        })
        .transpose()?;
    if override_value == Some(true) && !inherited && reason.is_none() {
        return Err(format!(
            "{location}.allow-test-panics = true requires allow-test-panics-reason"
        ));
    }
    Ok(override_value.unwrap_or(inherited))
}

pub fn resolve(request: &Request, packages: &[Package]) -> Result<Vec<Row>, String> {
    let default = effective(
        &request.metadata,
        request.default_allow_test_panics,
        "workspace.metadata",
    )?;
    select(packages, request)?
        .into_iter()
        .map(|package| {
            let relaxed = effective(
                &package.metadata,
                default,
                &format!("{}: package.metadata", package.manifest.display()),
            )?;
            Ok(Row {
                policy: if relaxed {
                    Policy::Relaxed
                } else {
                    Policy::Strict
                },
                spec: format!("{}@{}", package.name, package.version),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn member(name: &str, metadata: &Value) -> Result<Package, serde_json::Error> {
        serde_json::from_value(json!({
            "id": name, "name": name, "version": "1.0.0",
            "manifest": format!("/workspace/{name}/Cargo.toml"),
            "metadata": metadata, "targets": [], "candidates": {}
        }))
    }

    #[test]
    fn workspace_precedes_packages_and_excludes_apply() -> Result<(), Box<dyn std::error::Error>> {
        let packages = [
            member("a", &Value::Null)?,
            member(
                "b",
                &json!({"rust-skills2": {"allow-test-panics": true, "allow-test-panics-reason": "migration"}}),
            )?,
        ];
        let mut request = Request {
            default_allow_test_panics: false,
            cargo_args: vec!["--workspace".into(), "-p".into(), "a".into()],
            default_members: vec!["a".into()],
            metadata: Value::Null,
        };
        assert_eq!(
            resolve(&request, &packages)?,
            [
                Row {
                    policy: Policy::Strict,
                    spec: "a@1.0.0".into()
                },
                Row {
                    policy: Policy::Relaxed,
                    spec: "b@1.0.0".into()
                },
            ]
        );
        request.cargo_args.push("--exclude=a".into());
        assert_eq!(
            resolve(&request, &packages)?,
            [Row {
                policy: Policy::Relaxed,
                spec: "b@1.0.0".into()
            }]
        );
        request.cargo_args = vec!["--exclude=b".into()];
        assert!(resolve(&request, &packages).is_err());
        Ok(())
    }

    #[test]
    fn inherited_relaxation_can_only_be_strengthened_without_reason()
    -> Result<(), Box<dyn std::error::Error>> {
        let packages = [
            member("a", &json!({"rust-skills2": {"allow-test-panics": false}}))?,
            member("b", &Value::Null)?,
        ];
        let mut request = Request {
            default_allow_test_panics: false,
            cargo_args: vec!["--workspace".into()],
            default_members: vec![],
            metadata: json!({"rust-skills2": {"allow-test-panics": true}}),
        };
        assert!(resolve(&request, &packages).is_err());
        request.metadata = json!({"rust-skills2": {"allow-test-panics": true, "allow-test-panics-reason": "migration"}});
        assert_eq!(
            resolve(&request, &packages)?,
            [
                Row {
                    policy: Policy::Strict,
                    spec: "a@1.0.0".into()
                },
                Row {
                    policy: Policy::Relaxed,
                    spec: "b@1.0.0".into()
                },
            ]
        );
        request.cargo_args = vec!["-p".into(), "missing".into()];
        assert!(resolve(&request, &packages).is_err());
        Ok(())
    }
    #[test]
    fn package_selectors_defaults_and_exact_versions() -> Result<(), Box<dyn std::error::Error>> {
        let packages = [member("a", &Value::Null)?, member("b", &Value::Null)?];
        let mut request = Request {
            default_allow_test_panics: false,
            cargo_args: vec![],
            default_members: vec!["a".into()],
            metadata: Value::Null,
        };
        assert_eq!(resolve(&request, &packages)?.len(), 1);
        assert_eq!(resolve(&request, &packages)?[0].spec, "a@1.0.0");
        request.cargo_args = vec![
            "--package=b@1.0.0".into(),
            "-p".into(),
            "a".into(),
            "--package=b".into(),
        ];
        let rows = resolve(&request, &packages)?;
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].spec, "a@1.0.0");
        assert_eq!(rows[1].spec, "b@1.0.0");
        request.cargo_args = vec!["-p".into(), "missing".into()];
        assert!(resolve(&request, &packages).is_err());
        request.cargo_args = vec!["-p".into()];
        assert!(resolve(&request, &packages).is_err());
        request.cargo_args = vec!["--exclude=a".into()];
        assert!(resolve(&request, &packages).is_err());
        request.cargo_args = vec![
            "--workspace".into(),
            "--exclude=a".into(),
            "--exclude=b".into(),
        ];
        assert!(resolve(&request, &packages).is_err());
        request.cargo_args = vec!["--workspace".into(), "-p".into(), "missing".into()];
        assert!(resolve(&request, &packages).is_err());
        Ok(())
    }

    #[test]
    fn metadata_must_be_typed_and_relaxations_explained() -> Result<(), Box<dyn std::error::Error>>
    {
        let packages = [member("a", &Value::Null)?];
        let mut request = Request {
            default_allow_test_panics: false,
            cargo_args: vec!["--workspace".into()],
            default_members: vec![],
            metadata: json!({"rust-skills2":{"allow-test-panics":"yes"}}),
        };
        assert!(resolve(&request, &packages).is_err());
        request.metadata = json!({"rust-skills2":{"allow-test-panics-reason":" "}});
        assert!(resolve(&request, &packages).is_err());
        request.metadata = json!({"rust-skills2":{"allow-test-panics":true}});
        assert!(resolve(&request, &packages).is_err());
        request.metadata = json!({"rust-skills2":{
            "allow-test-panics":true,"allow-test-panics-reason":"upstream migration"
        }});
        assert_eq!(resolve(&request, &packages)?[0].policy, Policy::Relaxed);
        let no_reason = member("a", &json!({"rust-skills2":{"allow-test-panics":true}}))?;
        request.metadata = Value::Null;
        assert!(resolve(&request, &[no_reason]).is_err());
        let strict = member("a", &json!({"rust-skills2":{"allow-test-panics":false}}))?;
        request.default_allow_test_panics = true;
        assert_eq!(resolve(&request, &[strict])?[0].policy, Policy::Strict);
        Ok(())
    }
}
