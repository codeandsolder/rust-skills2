//! Frozen independent Python token expectations, evaluated by Rust directly.
use super::{lint_attributes, mask_noncode};
use serde::Deserialize;
use serde_json::Value;
use std::error::Error;

#[derive(Deserialize)]
struct Corpus {
    schema: u64,
    cases: Vec<TokenCase>,
}

#[derive(Deserialize)]
struct TokenCase {
    id: String,
    source: String,
    masked: String,
    attributes: Value,
}

fn cases() -> Result<Corpus, Box<dyn Error>> {
    let result: Corpus = serde_json::from_str(include_str!("../tests/golden/source-tokens.json"))?;
    assert_eq!(result.schema, 1);
    assert_eq!(result.cases.len(), 213);
    Ok(result)
}

#[test]
fn independent_token_mask_acceptance() -> Result<(), Box<dyn Error>> {
    let mut disagreements = Vec::new();
    for case in cases()?.cases {
        let masked = mask_noncode(&case.source);
        if masked != case.masked {
            disagreements.push(format!(
                "{}: Rust mask {masked:?} vs frozen reference {:?}",
                case.id, case.masked
            ));
        }
    }
    assert!(
        disagreements.is_empty(),
        "Token masking disagreements:\n{}",
        disagreements.join("\n")
    );
    Ok(())
}

#[test]
fn independent_lint_attribute_acceptance() -> Result<(), Box<dyn Error>> {
    let mut disagreements = Vec::new();
    for case in cases()?.cases {
        let attrs = serde_json::to_value(lint_attributes(&case.source))?;
        if attrs != case.attributes {
            disagreements.push(format!(
                "{}: Rust attributes {attrs} vs frozen reference {}",
                case.id, case.attributes
            ));
        }
    }
    assert!(
        disagreements.is_empty(),
        "Lint attribute disagreements:\n{}",
        disagreements.join("\n")
    );
    Ok(())
}
