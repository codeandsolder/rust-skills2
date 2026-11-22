"""Run the independent source-token reference scanner in Zipp."""

import json
import sys
from pathlib import Path

from checks.source_tokens import lint_attributes, mask_noncode


def regressions():
    literals = [
        "'\"'", "b'\"'", r"'\''", r"'\\'", r"'\x22'", r"'\u{22}'",
        "'['", "']'", "'🦀'",
    ]
    attribute = '#[expect(clippy::too_many_lines, reason = "fixture")]'
    for literal in literals:
        source = f"const C: char = {literal};\n{attribute}\nfn example() {{}}"
        found = lint_attributes(source)
        assert len(found) == 1, literal
        assert found[0][:3] == ("expect", ["clippy::too_many_lines"], True), literal
        assert source.count("\n", 0, found[0][3]) == 1, literal

    source = "fn f<'a>(x: &'a str) -> &'static str { 'outer: loop { break 'outer; } }"
    assert mask_noncode(source) == source

    source = """// #[allow(clippy::panic)]
/* nested /* #[warn(clippy::panic)] */ comment */
const S: &str = r###"#[allow(clippy::panic)]"###;
const T: &str = "#[allow(clippy::panic)]";
#[cfg_attr(test, expect(clippy::too_many_lines, reason = "fixture, with comma"))]
fn example() {}
"""
    masked = mask_noncode(source)
    assert len(masked) == len(source)
    assert masked.count("\n") == source.count("\n")
    assert [item[:3] for item in lint_attributes(source)] == [
        ("expect", ["clippy::too_many_lines"], True)
    ]

    # The scanner searches structural delimiters rather than walking every
    # character. Exercise complete and unterminated tokens, nested comments,
    # escaped quotes, raw hashes and non-BMP characters at arbitrary offsets.
    segments = [
        ("// comment 🦀", "\nfn after() {}"),
        ("/* outer\n/* nested */ still outer */", "fn after() {}"),
        ("/* unclosed /* nested */\n🦀", ""),
        ('"escaped \\" quote \n and 🦀"', "fn after() {}"),
        ('"trailing\\', ""),
        ('br###"embedded \\" ## \n🦀"###', "fn after() {}"),
        ('cr##"unterminated "# 🦀', ""),
        ("'🦀'", " 'lifetime"),
        ("b'\\x22'", " 'label: loop {}"),
    ]
    for token, suffix in segments:
        prefix = "ordinary code "
        expected = prefix + "".join("\n" if char == "\n" else " " for char in token) + suffix
        assert mask_noncode(prefix + token + suffix) == expected, repr(token)

    print("OK: independent source token masking regressions")


def corpus():
    sources = json.loads(Path("source-corpus.json").read_text(encoding="utf-8"))
    result = []
    for name, source in sources:
        attributes = [
            {"kind": kind, "lints": lints, "has_reason": reason,
             "line": source.count("\n", 0, offset) + 1}
            for kind, lints, reason, offset in lint_attributes(source)
        ]
        result.append([name, attributes])
    print(json.dumps(result))


if __name__ == "__main__":
    if len(sys.argv) == 1:
        regressions()
    elif sys.argv[1:] == ["corpus"]:
        corpus()
    else:
        raise SystemExit("unknown source oracle mode")
