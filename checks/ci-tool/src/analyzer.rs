//! Native Cargo compiler-evidence validator with exact per-block debt accounting.
use super::{Result, invalid};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write,
    fs,
    io::{BufRead, BufReader},
    path::{Component, Path, PathBuf},
};

type Manifest = BTreeMap<String, Value>;
type Diagnostics = BTreeMap<String, Vec<Value>>;

fn message_code(message: &Value) -> Option<&str> {
    message.get("code")?.get("code")?.as_str()
}

fn message_text(message: &Value) -> &str {
    message.get("message").and_then(Value::as_str).unwrap_or("")
}

fn resolution(message: &Value) -> bool {
    const CODES: [&str; 11] = [
        "E0432", "E0433", "E0412", "E0425", "E0405", "E0531", "E0422", "E0423", "E0573", "E0463",
        "E0583",
    ];
    const PREFIXES: [&str; 8] = [
        "cannot find",
        "unresolved import",
        "failed to resolve",
        "use of undeclared",
        "cannot determine",
        "can't find crate",
        "maybe a missing crate",
        "unresolved module",
    ];
    message_code(message).is_some_and(|code| CODES.contains(&code))
        || PREFIXES
            .iter()
            .any(|prefix| message_text(message).starts_with(prefix))
}

fn extraction_artifact(message: &Value) -> bool {
    let text = message_text(message);
    text.contains("parameter is only allowed in associated functions")
        || matches!(message_code(message), Some("E0586" | "E0585"))
        || text.contains("`...`")
        || text.contains("missing documentation")
        || text.contains("await is only allowed inside")
}

fn low_inference(message: &Value) -> bool {
    matches!(message_code(message), Some("E0282" | "E0283"))
}

fn diagnostic_token(message: &Value) -> String {
    if let Some(code) = message_code(message).filter(|code| !code.is_empty()) {
        return code.to_owned();
    }
    format!(
        "P:{}",
        message_text(message)
            .split_whitespace()
            .take(5)
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase()
    )
}

fn tokens(messages: &[Value]) -> String {
    let unique: BTreeSet<String> = messages.iter().map(diagnostic_token).collect();
    if unique.is_empty() {
        "COMPILED".to_owned()
    } else {
        unique.into_iter().collect::<Vec<_>>().join(",")
    }
}

#[derive(Debug, PartialEq, Eq)]
enum Legacy {
    Fragment,
    Artifact,
    Low,
    Suspect,
}

fn legacy(messages: &[Value]) -> Legacy {
    let actual: Vec<_> = messages
        .iter()
        .filter(|message| !resolution(message))
        .collect();
    if actual.is_empty() {
        return Legacy::Fragment;
    }
    if actual.iter().all(|message| extraction_artifact(message)) {
        return Legacy::Artifact;
    }
    let real: Vec<_> = actual
        .into_iter()
        .filter(|message| !extraction_artifact(message))
        .collect();
    if real.iter().all(|message| low_inference(message)) {
        Legacy::Low
    } else {
        Legacy::Suspect
    }
}

fn legacy_reason(messages: &[Value]) -> &'static str {
    if !messages.is_empty() && messages.iter().all(resolution) {
        "standalone fragment: unresolved context"
    } else {
        let actual: Vec<_> = messages
            .iter()
            .filter(|message| !resolution(message))
            .collect();
        if !actual.is_empty() && actual.iter().all(|message| extraction_artifact(message)) {
            "extraction artifact: wrapper/context"
        } else {
            let real: Vec<_> = actual
                .into_iter()
                .filter(|message| !extraction_artifact(message))
                .collect();
            if !real.is_empty() && real.iter().all(|message| low_inference(message)) {
                "standalone fragment: type inference needs surrounding context"
            } else {
                "legacy compile failure: repair example or add explicit rust-check metadata"
            }
        }
    }
}

fn canonical(path: &Path) -> Result<PathBuf> {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    if let Ok(canonical) = fs::canonicalize(&absolute) {
        return Ok(canonical);
    }
    // Compare lexical absolute paths for synthetic evidence before files exist.
    let mut clean = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                clean.pop();
            }
            other => clean.push(other.as_os_str()),
        }
    }
    Ok(clean)
}

/// Require Cargo JSONL to account for all generated examples and no foreign error.
fn parse(input: impl BufRead, manifest: &Manifest, source_dir: &Path) -> Result<Diagnostics> {
    let mut errors: Diagnostics = BTreeMap::new();
    let mut compiled = BTreeSet::new();
    let mut finished = Vec::new();
    for (line, raw) in input.lines().enumerate() {
        let raw = raw?;
        let raw = raw.trim();
        if !raw.starts_with('{') {
            continue;
        }
        let record: Value = serde_json::from_str(raw).map_err(|error| {
            invalid(format!("invalid Cargo JSON at line {}: {error}", line + 1))
        })?;
        let reason = record.get("reason").and_then(Value::as_str).unwrap_or("");
        if reason == "build-finished" {
            finished.push(record.get("success").and_then(Value::as_bool));
            continue;
        }
        if reason != "compiler-message" && reason != "compiler-artifact" {
            continue;
        }
        let target = &record["target"];
        let name = target.get("name").and_then(Value::as_str);
        let is_example = name.is_some_and(|name| {
            manifest.contains_key(name)
                && target
                    .get("kind")
                    .and_then(Value::as_array)
                    .is_some_and(|kinds| kinds.iter().any(|kind| kind == "example"))
                && target
                    .get("src_path")
                    .and_then(Value::as_str)
                    .is_some_and(|path| {
                        matches!(
                            (canonical(Path::new(path)), canonical(&source_dir.join(format!("{name}.rs")))),
                            (Ok(candidate), Ok(expected)) if candidate == expected
                        )
                    })
        });
        if reason == "compiler-artifact" {
            if is_example && let Some(name) = name {
                compiled.insert(name.to_owned());
            }
            continue;
        }
        let message = &record["message"];
        if message.get("level").and_then(Value::as_str) != Some("error") {
            continue;
        }
        if !is_example {
            return Err(invalid(format!(
                "error outside generated examples: {}: {}",
                name.unwrap_or("None"),
                message_text(message),
            ))
            .into());
        }
        if let Some(name) = name {
            errors
                .entry(name.to_owned())
                .or_default()
                .push(message.clone());
        }
    }
    if finished.len() != 1 || finished[0].is_none() {
        return Err(
            invalid("Cargo output must contain exactly one valid build-finished record").into(),
        );
    }
    let missing: Vec<_> = manifest
        .iter()
        .filter(|(_, info)| info.get("generated").and_then(Value::as_bool) != Some(false))
        .map(|(name, _)| name)
        .filter(|name| !compiled.contains(*name) && !errors.contains_key(*name))
        .cloned()
        .collect();
    if !missing.is_empty() {
        return Err(invalid(format!(
            "Cargo did not check generated examples: {}",
            missing.join(", ")
        ))
        .into());
    }
    if finished[0] == Some(false) && errors.is_empty() {
        return Err(invalid(
            "Cargo failed without any generated-example error diagnostics; inspect check.err",
        )
        .into());
    }
    if finished[0] == Some(true) && !errors.is_empty() {
        return Err(invalid("Cargo reported success despite error diagnostics").into());
    }
    Ok(errors)
}

fn signature(name: &str, diagnostics: &[Value], manifest: &Manifest) -> String {
    let info = &manifest[name];
    let ordinal = name
        .rsplit_once("__")
        .and_then(|(_, index)| index.parse::<usize>().ok())
        .and_then(|index| index.checked_add(1))
        .map_or_else(|| "?".to_owned(), |index| index.to_string());
    format!(
        "{} :: {} :: block {ordinal} :: {}",
        info.get("file").and_then(Value::as_str).unwrap_or("?"),
        info.get("section").and_then(Value::as_str).unwrap_or("?"),
        tokens(diagnostics),
    )
}

#[derive(Default)]
struct Findings {
    automatic: BTreeSet<String>,
    violations: BTreeMap<String, (String, String, Vec<Value>)>,
    counts: BTreeMap<String, usize>,
    generated: usize,
    failed: usize,
}

fn collect(manifest: &Manifest, errors: &Diagnostics) -> Result<Findings> {
    let mut found = Findings {
        failed: errors.len(),
        ..Findings::default()
    };
    for (name, info) in manifest {
        let kind = info.get("expect").and_then(Value::as_str).unwrap_or("auto");
        *found.counts.entry(kind.to_owned()).or_default() += 1;
        if info.get("generated").and_then(Value::as_bool) == Some(false) {
            continue;
        }
        found.generated += 1;
        let messages = errors.get(name).map_or(&[][..], Vec::as_slice);
        let why = match kind {
            "compile" if !messages.is_empty() => Some("expected compile"),
            "fragment" if !messages.is_empty() && legacy(messages) == Legacy::Suspect => {
                Some("fragment has non-fragment errors")
            }
            "compile_fail" if messages.is_empty() => Some("expected compile failure, but compiled"),
            "auto" => {
                let classification = legacy(messages);
                let text = match classification {
                    Legacy::Fragment => "fragment",
                    Legacy::Artifact => "artifact",
                    Legacy::Low => "low",
                    Legacy::Suspect => "suspect",
                };
                *found.counts.entry(format!("auto:{text}")).or_default() += 1;
                if classification == Legacy::Suspect {
                    let suspects: Vec<_> = messages
                        .iter()
                        .filter(|message| {
                            !resolution(message)
                                && !extraction_artifact(message)
                                && !low_inference(message)
                        })
                        .cloned()
                        .collect();
                    found.automatic.insert(signature(name, &suspects, manifest));
                }
                None
            }
            "compile" | "compile_fail" | "fragment" => None,
            _ => {
                return Err(
                    invalid(format!("unknown generated expectation {kind:?} for {name}")).into(),
                );
            }
        };
        if let Some(why) = why {
            found.violations.insert(
                signature(name, messages, manifest),
                (name.clone(), why.to_owned(), messages.to_vec()),
            );
        }
    }
    Ok(found)
}

fn baseline(path: &Path) -> Result<BTreeSet<String>> {
    let contents = fs::read_to_string(path)?;
    Ok(contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(str::to_owned)
        .collect())
}

fn good_exceptions(path: &Path) -> Result<BTreeMap<String, String>> {
    if !path.exists() {
        return Ok(BTreeMap::new());
    }
    parse_good_exceptions(&fs::read_to_string(path)?)
}

fn parse_good_exceptions(contents: &str) -> Result<BTreeMap<String, String>> {
    let mut entries = BTreeMap::new();
    for line in contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
    {
        let (signature, reason) = line
            .split_once(" || ")
            .ok_or_else(|| invalid(format!("bad good-exceptions line (missing ' || '): {line}")))?;
        if reason.trim().is_empty() {
            return Err(
                invalid(format!("good-exceptions entry has no reason: {signature}")).into(),
            );
        }
        if !signature.contains(" :: block ") {
            return Err(invalid(format!(
                "good-exceptions entry does not identify an exact block: {signature}"
            ))
            .into());
        }
        entries.insert(signature.trim().to_owned(), reason.trim().to_owned());
    }
    Ok(entries)
}

fn check(
    findings: &Findings,
    baseline: &BTreeSet<String>,
    good: &BTreeMap<String, String>,
) -> Result<String> {
    let current_good: BTreeSet<_> = findings.violations.keys().cloned().collect();
    let allowed_good: BTreeSet<_> = good.keys().cloned().collect();
    let new_good: Vec<_> = current_good.difference(&allowed_good).collect();
    let stale_good: Vec<_> = allowed_good.difference(&current_good).collect();
    let new_auto: Vec<_> = findings.automatic.difference(baseline).collect();
    let stale_auto: Vec<_> = baseline.difference(&findings.automatic).collect();
    let mut text = String::new();
    if !new_good.is_empty() {
        writeln!(
            text,
            "FAIL: {} recommended/explicit expectation violation(s):\n",
            new_good.len()
        )?;
        for signature in new_good {
            writeln!(text, "  + {signature}")?;
        }
        writeln!(
            text,
            "\nFix the example or add explicit `rust-check` metadata. During migration only, an exact debt entry with a reason may be added to good-exceptions.txt.\n"
        )?;
    }
    if !stale_good.is_empty() {
        writeln!(
            text,
            "FAIL: {} stale good-exception(s); remove them because the exact failure is gone:\n",
            stale_good.len()
        )?;
        for signature in stale_good {
            writeln!(text, "  - {signature}")?;
        }
        writeln!(text)?;
    }
    if !new_auto.is_empty() {
        writeln!(
            text,
            "FAIL: {} new legacy compile-suspect(s) not in baseline:\n",
            new_auto.len()
        )?;
        for signature in new_auto {
            writeln!(text, "  + {signature}")?;
        }
        writeln!(text)?;
    }
    if !stale_auto.is_empty() {
        writeln!(
            text,
            "FAIL: {} stale legacy baseline entrie(s); remove them because the exact failure is gone:\n",
            stale_auto.len()
        )?;
        for signature in stale_auto {
            writeln!(text, "  - {signature}")?;
        }
        writeln!(text)?;
    }
    if !text.is_empty() {
        return Err(invalid(text).into());
    }
    writeln!(
        text,
        "OK: expectations satisfied ({} exact recommended-example debt entries); legacy baseline exact and current ({} signatures)",
        good.len(),
        findings.automatic.len()
    )?;
    Ok(text)
}

fn summary(findings: &Findings, manifest: &Manifest) -> Result<String> {
    let mut output = String::new();
    writeln!(output, "== compile-check summary ==")?;
    writeln!(output, "examples generated        : {}", findings.generated)?;
    writeln!(
        output,
        "compiled clean            : {}",
        findings.generated.saturating_sub(findings.failed)
    )?;
    writeln!(
        output,
        "expectation violations    : {}",
        findings.violations.len()
    )?;
    writeln!(
        output,
        "legacy auto suspects      : {}",
        findings.automatic.len()
    )?;
    let counts = findings
        .counts
        .iter()
        .filter(|(name, _)| !name.contains(':'))
        .map(|(name, count)| format!("{name}={count}"))
        .collect::<Vec<_>>()
        .join(", ");
    writeln!(output, "expectation counts        : {counts}")?;
    let mut violations: Vec<_> = findings.violations.values().collect();
    violations.sort_by_key(|(name, _, _)| {
        let info = &manifest[name];
        (
            info.get("file")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned(),
            info.get("line").and_then(Value::as_u64).unwrap_or(0),
        )
    });
    for (name, why, messages) in violations {
        let info = &manifest[name];
        writeln!(
            output,
            "\n--- {}:{} [{}] — {why}",
            info.get("file").and_then(Value::as_str).unwrap_or("?"),
            info.get("line").and_then(Value::as_u64).unwrap_or(0),
            info.get("section").and_then(Value::as_str).unwrap_or("?"),
        )?;
        if messages.is_empty() {
            writeln!(output, "    compiled successfully")?;
        } else {
            let mut seen = BTreeSet::new();
            for message in messages {
                let code = message_code(message).unwrap_or("----");
                let text = message_text(message).lines().next().unwrap_or("");
                if seen.insert((code, text)) {
                    writeln!(output, "    {code}: {text}")?;
                }
            }
        }
    }
    Ok(output)
}

#[derive(Default)]
struct Options {
    evidence: Option<PathBuf>,
    manifest: Option<PathBuf>,
    source_dir: Option<PathBuf>,
    baseline: Option<PathBuf>,
    good_exceptions: Option<PathBuf>,
    emit_baseline: bool,
    emit_good: bool,
}

fn options(args: &[String]) -> Result<Options> {
    let mut result = Options::default();
    let mut args = args.iter();
    while let Some(option) = args.next() {
        match option.as_str() {
            "--input" => {
                result.evidence = Some(PathBuf::from(
                    args.next().ok_or_else(|| invalid("--input needs path"))?,
                ));
            }
            "--manifest" => {
                result.manifest = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| invalid("--manifest needs path"))?,
                ));
            }
            "--source-dir" => {
                result.source_dir = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| invalid("--source-dir needs path"))?,
                ));
            }
            "--check-baseline" => {
                result.baseline = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| invalid("--check-baseline needs path"))?,
                ));
            }
            "--good-exceptions" => {
                result.good_exceptions = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| invalid("--good-exceptions needs path"))?,
                ));
            }
            "--emit-baseline" => result.emit_baseline = true,
            "--emit-good-exceptions" => result.emit_good = true,
            _ => return Err(invalid(format!("unknown analyzer argument: {option}")).into()),
        }
    }
    if result.emit_baseline && result.emit_good {
        return Err(invalid("choose at most one analyzer emission mode").into());
    }
    if (result.emit_baseline || result.emit_good) && result.baseline.is_some() {
        return Err(invalid("cannot emit and check a baseline simultaneously").into());
    }
    Ok(result)
}

/// Analyze Cargo JSON compiler output against exact extracted-example contracts.
///
/// # Errors
/// Returns an error for malformed or incomplete Cargo evidence, changing compiler
/// diagnostics, stale baseline allowances or violated expectation contracts.
pub fn run(root: &Path, args: &[String]) -> Result<()> {
    let opts = options(args)?;
    let checks = root.join("checks");
    let manifest: Manifest = serde_json::from_str(&fs::read_to_string(
        opts.manifest
            .unwrap_or_else(|| checks.join("manifest.json")),
    )?)?;
    let evidence = fs::File::open(opts.evidence.unwrap_or_else(|| checks.join("check.json")))?;
    let source_dir = opts.source_dir.unwrap_or_else(|| checks.join("examples"));
    let errors = parse(BufReader::new(evidence), &manifest, &source_dir)?;
    let found = collect(&manifest, &errors)?;
    if opts.emit_baseline {
        for signature in &found.automatic {
            println!("{signature}");
        }
        return Ok(());
    }
    if opts.emit_good {
        for (signature, (_, _, messages)) in &found.violations {
            println!("{signature} || {}", legacy_reason(messages));
        }
        return Ok(());
    }
    if let Some(path) = opts.baseline {
        print!(
            "{}",
            check(
                &found,
                &baseline(&path)?,
                &good_exceptions(
                    &opts
                        .good_exceptions
                        .unwrap_or_else(|| checks.join("good-exceptions.txt"))
                )?
            )?
        );
    } else {
        print!("{}", summary(&found, &manifest)?);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Cursor;

    const SOURCE_DIR: &str = "/checkout/checks/examples";

    fn manifest() -> Manifest {
        BTreeMap::from([(
            "sample".to_owned(),
            json!({"expect": "compile", "file": "rule.md", "section": "Good", "line": 9, "generated": true}),
        )])
    }

    fn target(name: &str) -> Value {
        json!({
            "name": name, "kind": ["example"],
            "src_path": format!("{SOURCE_DIR}/{name}.rs")
        })
    }

    fn artifact(fresh: bool) -> Value {
        json!({"reason": "compiler-artifact", "target": target("sample"), "fresh": fresh})
    }

    fn error() -> Value {
        json!({"reason": "compiler-message", "target": target("sample"),
            "message": {"level": "error", "code": {"code": "E0308"}, "message": "mismatched types"}})
    }

    fn done(success: bool) -> Value {
        json!({"reason": "build-finished", "success": success})
    }

    fn parse_records(records: &[Value], manifest: &Manifest) -> Result<Diagnostics> {
        let input = records
            .iter()
            .map(Value::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        parse(Cursor::new(input), manifest, Path::new(SOURCE_DIR))
    }

    fn invalid_evidence(records: &[Value], manifest: &Manifest, phrase: &str) -> Result<()> {
        let result = parse_records(records, manifest)
            .err()
            .ok_or_else(|| invalid("invalid evidence accepted"))?;
        assert!(result.to_string().contains(phrase), "{result}");
        Ok(())
    }

    #[test]
    fn actual_cargo_evidence_contract() -> Result<()> {
        for fresh in [false, true] {
            assert!(parse_records(&[artifact(fresh), done(true)], &manifest())?.is_empty());
        }
        let errors = parse_records(&[error(), done(false)], &manifest())?;
        assert_eq!(errors["sample"], vec![error()["message"].clone()]);
        for records in [
            vec![],
            vec![artifact(false)],
            vec![artifact(false), done(true), done(true)],
        ] {
            invalid_evidence(&records, &manifest(), "exactly one")?;
        }
        invalid_evidence(&[done(true)], &manifest(), "did not check")?;
        let mut warning = error();
        warning["message"]["level"] = json!("warning");
        invalid_evidence(&[warning, done(true)], &manifest(), "did not check")?;
        let mut missing = manifest();
        missing.insert("missing".into(), json!({}));
        invalid_evidence(&[error(), done(false)], &missing, "missing")?;
        let mut dep = error();
        dep["target"]["kind"] = json!(["lib"]);
        invalid_evidence(&[dep, done(false)], &manifest(), "outside generated")?;
        let mut wrong = artifact(false);
        wrong["target"]["src_path"] = json!("/other/sample.rs");
        invalid_evidence(&[wrong, done(true)], &manifest(), "did not check")?;
        let mut skipped = Manifest::new();
        skipped.insert("fixture".into(), json!({"generated": false}));
        assert!(parse_records(&[done(true)], &skipped)?.is_empty());
        invalid_evidence(
            &[artifact(false), done(false)],
            &manifest(),
            "failed without",
        )?;
        invalid_evidence(&[error(), done(true)], &manifest(), "reported success")?;
        let malformed = parse(
            Cursor::new("{\"reason\":"),
            &manifest(),
            Path::new(SOURCE_DIR),
        );
        assert!(malformed.is_err());
        assert!(
            malformed
                .err()
                .is_some_and(|err| err.to_string().contains("invalid Cargo JSON"))
        );
        Ok(())
    }

    #[test]
    fn compiler_errors_must_be_accounted_for_even_in_transitive_sources() -> Result<()> {
        let mut unrelated = error();
        unrelated["target"]["name"] = json!("dep");
        invalid_evidence(&[unrelated, done(false)], &manifest(), "outside generated")?;
        let broken = json!({"reason":"build-finished","success":"true"});
        invalid_evidence(&[artifact(false), broken], &manifest(), "exactly one")?;
        let malformed = json!({"reason":"build-finished","success":null});
        invalid_evidence(&[artifact(false), malformed], &manifest(), "exactly one")?;
        Ok(())
    }

    #[test]
    fn diagnostic_classification_and_exemption_reasons() {
        let cases = [
            (
                json!({"code":{"code":"E0433"},"message":"failed to resolve"}),
                Legacy::Fragment,
                "standalone fragment: unresolved context",
            ),
            (
                json!({"code":{"code":"E0585"},"message":"documentation extraction"}),
                Legacy::Artifact,
                "extraction artifact: wrapper/context",
            ),
            (
                json!({"code":{"code":"E0282"},"message":"type annotation needed"}),
                Legacy::Low,
                "standalone fragment: type inference needs surrounding context",
            ),
            (
                json!({"code":{"code":"E0308"},"message":"type mismatch"}),
                Legacy::Suspect,
                "legacy compile failure: repair example or add explicit rust-check metadata",
            ),
            (
                json!({"code":null,"message":"unresolved import abc"}),
                Legacy::Fragment,
                "standalone fragment: unresolved context",
            ),
            (
                json!({"code":null,"message":"missing documentation for foo"}),
                Legacy::Artifact,
                "extraction artifact: wrapper/context",
            ),
        ];
        for (message, category, reason) in cases {
            let inputs = [message];
            assert_eq!(legacy(&inputs), category);
            assert_eq!(legacy_reason(&inputs), reason);
        }
        assert_eq!(legacy(&[]), Legacy::Fragment);
        assert_eq!(
            legacy(&[
                json!({"code":{"code":"E0433"}, "message":"unresolved import"}),
                json!({"code":{"code":"E0308"}, "message":"type mismatch"}),
            ]),
            Legacy::Suspect
        );
        assert_eq!(
            diagnostic_token(&json!({"message":"  TEST   Multiple  WORDS are HERE and ignored  "})),
            "P:test multiple words are here"
        );
    }

    #[test]
    fn exact_signature_and_debt_integrity() -> Result<()> {
        let mut entries = manifest();
        entries.insert(
            "skip__7".into(),
            json!({"expect":"nightly","generated":false}),
        );
        let errors = Diagnostics::from([(
            "sample".to_owned(),
            vec![json!({"code":{"code":"E0308"},"message":"types"})],
        )]);
        let found = collect(&entries, &errors)?;
        let key = "rule.md :: Good :: block ? :: E0308";
        assert!(found.violations.contains_key(key));
        let good = BTreeMap::from([(key.to_owned(), "investigate".to_owned())]);
        assert!(check(&found, &BTreeSet::new(), &good)?.contains("expectations satisfied"));
        assert!(
            check(&found, &BTreeSet::new(), &BTreeMap::new())
                .err()
                .is_some_and(|err| err.to_string().contains("recommended/explicit"))
        );
        assert!(
            check(&Findings::default(), &BTreeSet::new(), &good)
                .err()
                .is_some_and(|err| err.to_string().contains("stale good-exception"))
        );
        let auto_info =
            json!({"expect":"auto", "file":"rule.md", "section":"Overview", "generated":true});
        let auto = Manifest::from([("example__2".into(), auto_info)]);
        let suspect = Diagnostics::from([(
            "example__2".to_owned(),
            vec![json!({"code":{"code":"E0308"},"message":"types"})],
        )]);
        let auto_found = collect(&auto, &suspect)?;
        assert!(
            auto_found
                .automatic
                .contains("rule.md :: Overview :: block 3 :: E0308")
        );
        let expired = BTreeSet::from(["old.md :: Section :: block 1 :: E0001".to_owned()]);
        let output = check(&auto_found, &expired, &BTreeMap::new())
            .err()
            .ok_or_else(|| invalid("accepted stale legacy debt"))?
            .to_string();
        assert!(output.contains("new legacy compile-suspect"));
        assert!(output.contains("stale legacy baseline"));
        Ok(())
    }

    #[test]
    fn all_expectations_and_rejected_generated_contracts() -> Result<()> {
        for (expect, failed, violations) in [
            ("compile", false, 0),
            ("compile", true, 1),
            ("compile_fail", false, 1),
            ("compile_fail", true, 0),
            ("fragment", false, 0),
            ("fragment", true, 1),
            ("auto", false, 0),
            ("auto", true, 0),
        ] {
            let entries = Manifest::from([(
                "sample__0".into(),
                json!({
                    "expect": expect, "file":"rule.md", "section":"Good", "generated":true
                }),
            )]);
            let errors = if failed {
                Diagnostics::from([(
                    "sample__0".into(),
                    vec![json!({"code":{"code":"E0308"},"message":"types"})],
                )])
            } else {
                Diagnostics::new()
            };
            assert_eq!(collect(&entries, &errors)?.violations.len(), violations);
        }
        let bad = Manifest::from([("sample".into(), json!({"expect":"not-an-expectation"}))]);
        assert!(collect(&bad, &Diagnostics::new()).is_err());
        Ok(())
    }

    #[test]
    fn canonical_source_identity_rejects_lexically_different_paths() -> Result<()> {
        let candidate = canonical(Path::new(
            "/checkout/checks/./examples/../examples/sample.rs",
        ))?;
        let expected = canonical(Path::new("/checkout/checks/examples/sample.rs"))?;
        assert_eq!(candidate, expected);
        let other = canonical(Path::new("/checkout/checks/tests/sample.rs"))?;
        assert_ne!(candidate, other);
        Ok(())
    }
    #[test]
    fn legacy_signatures_exclude_resolution_artifacts_and_inference_noise() -> Result<()> {
        let entry = Manifest::from([(
            "sample__4".into(),
            json!({
                "file":"nested.md", "section":"Legacy", "expect":"auto", "generated":true
            }),
        )]);
        let diagnostics = vec![
            json!({"code":{"code":"E0433"},"message":"failed to resolve"}),
            json!({"code":{"code":"E0282"},"message":"type inference"}),
            json!({"code":{"code":"E0585"},"message":"invalid documentation"}),
            json!({"code":{"code":"E0308"},"message":"mismatched types"}),
            json!({"code":null,"message":"other invalid example outside scope"}),
        ];
        let findings = collect(
            &entry,
            &Diagnostics::from([("sample__4".into(), diagnostics)]),
        )?;
        assert_eq!(
            findings.automatic,
            BTreeSet::from([
                "nested.md :: Legacy :: block 5 :: E0308,P:other invalid example outside scope"
                    .to_owned()
            ])
        );
        Ok(())
    }

    #[test]
    fn rejects_malformed_debt_and_preserves_exact_block_identity() -> Result<()> {
        let good = parse_good_exceptions(
            "# Reference entries\nrule.md :: Good :: block 2 :: E0308 || explanation\n",
        )?;
        assert_eq!(good["rule.md :: Good :: block 2 :: E0308"], "explanation");
        for bad in [
            "rule.md :: Good :: block 2 :: E0308",
            "rule.md :: Good :: block 2 :: E0308 ||   ",
            "rule.md :: Good :: E0308 || vague",
        ] {
            assert!(parse_good_exceptions(bad).is_err(), "{bad}");
        }
        let bad = options(&["--emit-baseline".into(), "--emit-good-exceptions".into()]);
        assert!(bad.is_err());
        let bad = options(&["--unknown-option".into()]);
        assert!(bad.is_err());
        Ok(())
    }
}
