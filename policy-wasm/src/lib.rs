use regex::Regex;
use serde::Serialize;
use std::sync::LazyLock;

pub mod check;
pub mod policy;
mod workspace;

static CHARACTER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^(?:b)?'(?:[^'\\\n\r\t]|\\(?:[nrt\\0'"]|x[0-9A-Fa-f]{2}|u\{[0-9A-Fa-f_]+\}))'"#)
        .unwrap_or_else(|error| unreachable!("invalid static character pattern: {error}"))
});
static ATTRIBUTE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"#\s*!?\s*\[")
        .unwrap_or_else(|error| unreachable!("invalid static attribute pattern: {error}"))
});
static HEAD: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*([A-Za-z_][A-Za-z0-9_-]*)\b")
        .unwrap_or_else(|error| unreachable!("invalid static head pattern: {error}"))
});
static CALL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b(allow|warn|expect)\s*\(")
        .unwrap_or_else(|error| unreachable!("invalid static call pattern: {error}"))
});
static LINT_PATH: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*([A-Za-z_][A-Za-z0-9_-]*(?:::[A-Za-z_][A-Za-z0-9_-]*)*)\s*$")
        .unwrap_or_else(|error| unreachable!("invalid static lint pattern: {error}"))
});
static REASON: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*reason\s*=")
        .unwrap_or_else(|error| unreachable!("invalid static reason pattern: {error}"))
});

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Attribute {
    pub kind: String,
    pub lints: Vec<String>,
    pub has_reason: bool,
    pub line: usize,
}

fn raw_prefix(bytes: &[u8]) -> Option<(usize, usize)> {
    let rest = if matches!(bytes.first(), Some(b'b' | b'c')) {
        bytes.get(1..)?
    } else {
        bytes
    };
    let rest = rest.strip_prefix(b"r")?;
    let hashes = rest.iter().take_while(|&&byte| byte == b'#').count();
    (rest.get(hashes) == Some(&b'"')).then_some((bytes.len() - rest.len() + hashes + 1, hashes))
}

fn quoted_end(bytes: &[u8], mut cursor: usize) -> usize {
    while let Some(&byte) = bytes.get(cursor) {
        cursor += 1;
        match byte {
            b'\\' => cursor = (cursor + 1).min(bytes.len()),
            b'"' => break,
            _ => {}
        }
    }
    cursor
}

fn raw_end(bytes: &[u8], mut cursor: usize, hashes: usize) -> usize {
    while let Some(&byte) = bytes.get(cursor) {
        cursor += 1;
        if byte == b'"'
            && bytes
                .get(cursor..cursor + hashes)
                .is_some_and(|suffix| suffix.iter().all(|&b| b == b'#'))
        {
            return cursor + hashes;
        }
    }
    cursor
}

fn block_end(bytes: &[u8], mut cursor: usize) -> usize {
    let mut depth = 1;
    while cursor < bytes.len() && depth != 0 {
        if bytes[cursor..].starts_with(b"/*") {
            depth += 1;
            cursor += 2;
        } else if bytes[cursor..].starts_with(b"*/") {
            depth -= 1;
            cursor += 2;
        } else {
            cursor += 1;
        }
    }
    cursor
}

/// Mask comments and literals in one pass, retaining UTF-8 byte offsets and line breaks.
fn mask_noncode(source: &str) -> String {
    let bytes = source.as_bytes();
    let mut masked = bytes.to_vec();
    let mut cursor = 0;
    while cursor < bytes.len() {
        let rest = &bytes[cursor..];
        let end = match rest.first() {
            Some(b'/') if rest.starts_with(b"//") => {
                cursor + memchr::memchr(b'\n', rest).unwrap_or(rest.len())
            }
            Some(b'/') if rest.starts_with(b"/*") => block_end(bytes, cursor + 2),
            Some(b'\'' | b'b') if rest.starts_with(b"'") || rest.starts_with(b"b'") => {
                let Some(literal) = source.get(cursor..).and_then(|s| CHARACTER.find(s)) else {
                    cursor += 1;
                    continue;
                };
                cursor + literal.end()
            }
            Some(b'"') => quoted_end(bytes, cursor + 1),
            Some(b'b' | b'c') if rest.get(1) == Some(&b'"') => quoted_end(bytes, cursor + 2),
            Some(b'r' | b'b' | b'c') => {
                let Some((prefix, hashes)) = raw_prefix(rest) else {
                    cursor += 1;
                    continue;
                };
                raw_end(bytes, cursor + prefix, hashes)
            }
            _ => {
                cursor += 1;
                continue;
            }
        };
        for byte in &mut masked[cursor..end] {
            if *byte != b'\n' {
                *byte = b' ';
            }
        }
        cursor = end;
    }
    String::from_utf8(masked)
        .unwrap_or_else(|error| unreachable!("mask must retain valid UTF-8: {error}"))
}

fn matching(text: &[u8], start: usize, opening: u8, closing: u8) -> Option<usize> {
    let mut depth = 0;
    for (offset, &byte) in text.iter().enumerate().skip(start) {
        if byte == opening {
            depth += 1;
        } else if byte == closing {
            depth -= 1;
            if depth == 0 {
                return Some(offset);
            }
        }
    }
    None
}

/// Return lint attributes with source line numbers; string/comment bytes never act as syntax.
#[must_use = "the extracted attributes are the input to policy evaluation"]
pub fn lint_attributes(source: &str) -> Vec<Attribute> {
    if memchr::memchr(b'#', source.as_bytes()).is_none() {
        return Vec::new();
    }
    let masked = mask_noncode(source);
    let mut found = Vec::new();
    let mut last_offset = 0;
    let mut line = 1;
    for attribute in ATTRIBUTE.find_iter(&masked) {
        let open = attribute.end() - 1;
        let Some(close) = matching(masked.as_bytes(), open, b'[', b']') else {
            continue;
        };
        let body = &masked[open + 1..close];
        if !HEAD
            .captures(body)
            .and_then(|m| m.get(1))
            .is_some_and(|head| matches!(head.as_str(), "allow" | "warn" | "expect" | "cfg_attr"))
        {
            continue;
        }
        for call in CALL.captures_iter(body) {
            let (Some(full), Some(kind)) = (call.get(0), call.get(1)) else {
                continue;
            };
            let offset = open + 1 + full.start();
            let paren = open + full.end();
            let Some(end) = matching(masked.as_bytes(), paren, b'(', b')') else {
                continue;
            };
            if end > close {
                continue;
            }
            let mut lints = Vec::new();
            let mut has_reason = false;
            for item in masked[paren + 1..end].split(',') {
                if REASON.is_match(item) {
                    has_reason = true;
                } else if let Some(path) = LINT_PATH.captures(item).and_then(|m| m.get(1)) {
                    lints.push(path.as_str().replace('-', "_"));
                }
            }
            // Attributes nested in macro token trees may be visited in a different order.
            if offset < last_offset {
                line = 1;
                last_offset = 0;
            }
            line += memchr::memchr_iter(b'\n', &source.as_bytes()[last_offset..offset]).count();
            last_offset = offset;
            found.push(Attribute {
                kind: kind.as_str().to_owned(),
                lints,
                has_reason,
                line,
            });
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn comments_literals_and_lifetimes() {
        let source = r####"// #[allow(clippy::panic)]
/* nested /* #[warn(clippy::panic)] */ comment */
const S: &str = r###"#[allow(clippy::panic)]"###;
const T: &str = "#[allow(clippy::panic)]";
const C: char = '🦀';
fn f<'a>(x: &'a str) -> &'a str { 'outer: loop { break 'outer; } x }
#[cfg_attr(test, expect(clippy::too_many_lines, reason = "fixture, with comma"))]
fn example() {}"####;
        let attributes = lint_attributes(source);
        assert_eq!(
            attributes,
            [Attribute {
                kind: "expect".into(),
                lints: vec!["clippy::too_many_lines".into()],
                has_reason: true,
                line: 7
            }]
        );
        let lifetimes = "fn f<'a>(x: &'a str) -> &'static str { 'outer: loop { break 'outer; } }";
        assert_eq!(mask_noncode(lifetimes), lifetimes);
    }

    #[test]
    fn all_character_forms_preserve_following_attributes() {
        for literal in [
            "'\"'",
            "b'\"'",
            r"'\''",
            r"'\\'",
            r"'\x22'",
            r"'\u{22}'",
            "'['",
            "']'",
            "'🦀'",
        ] {
            let source = format!(
                "const C: char = {literal};\n#[expect(clippy::too_many_lines, reason = \"fixture\")]\nfn example() {{}}"
            );
            assert_eq!(
                lint_attributes(&source),
                [Attribute {
                    kind: "expect".into(),
                    lints: vec!["clippy::too_many_lines".into()],
                    has_reason: true,
                    line: 2
                }]
            );
        }
    }

    #[test]
    fn multiple_nested_calls() {
        let source = "#[cfg_attr(test, expect(clippy::foo, reason = \"x\"), warn(clippy::bar))]\n#![allow(dead_code, unused)]";
        let attributes = lint_attributes(source);
        assert_eq!(attributes.len(), 3);
        assert_eq!(attributes[0].lints, ["clippy::foo"]);
        assert_eq!(attributes[1].kind, "warn");
        assert_eq!(attributes[2].lints, ["dead_code", "unused"]);
    }
}
