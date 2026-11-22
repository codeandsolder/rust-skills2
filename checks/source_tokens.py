"""Independent Python reference for Rust source token and lint-attribute scanning."""

from __future__ import annotations

import re


def normalize_lint(name: str) -> str:
    return name.strip().replace("-", "_")


RUST_CHARACTER = re.compile(
    r"(?:b)?'(?:[^'\\\n\r\t]|\\(?:[nrt\\0'\"]|x[0-9A-Fa-f]{2}|u\{[0-9A-Fa-f_]+\}))'"
)
RUST_RAW_STRING = re.compile(r"(?:b|c)?r(#+)?\"")

# Search only for actual token openings; ordinary Rust code needs no masking.
# Alternatives preserve the original precedence at each source position.
TOKEN_OPEN = re.compile(r"//|/\*|" + RUST_CHARACTER.pattern + "|" + RUST_RAW_STRING.pattern + r'|b"|c"|"')


def mask_noncode(text: str) -> str:
    """Mask comments and string literals while preserving length/newlines."""
    masked = list(text)
    length = len(text)
    i = 0

    def blank(start: int, end: int) -> None:
        for index in range(start, end):
            if masked[index] != "\n":
                masked[index] = " "

    while i < length:
        opening = TOKEN_OPEN.search(text, i)
        if opening is None:
            break
        i = opening.start()
        if text.startswith("//", i):
            end = text.find("\n", i + 2)
            if end == -1:
                end = length
            blank(i, end)
            i = end
            continue

        if text.startswith("/*", i):
            start = i
            depth = 1
            i += 2
            while i < length and depth:
                if text.startswith("/*", i):
                    depth += 1
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            blank(start, i)
            continue

        # A quote character such as '\"' must not start a string that swallows
        # subsequent attributes. Require a complete character token so lifetimes
        # and labels ('a, 'static, 'outer:) remain code.
        char_literal = RUST_CHARACTER.match(text, i)
        if char_literal is not None:
            end = char_literal.end()
            blank(i, end)
            i = end
            continue

        raw = RUST_RAW_STRING.match(text, i)
        if raw is not None:
            start = i
            hashes = raw.group(1) or ""
            i = raw.end()
            terminator = '"' + hashes
            end = text.find(terminator, i)
            i = length if end == -1 else end + len(terminator)
            blank(start, i)
            continue

        string_prefix = None
        for prefix in ('b"', 'c"', '"'):
            if text.startswith(prefix, i):
                string_prefix = prefix
                break
        if string_prefix is not None:
            start = i
            i += len(string_prefix)
            escaped = False
            while i < length:
                char = text[i]
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    i += 1
                    break
                i += 1
            blank(start, i)
            continue

        raise AssertionError("unrecognized token opening")

    return "".join(masked)


def matching(text: str, start: int, opening: str, closing: str) -> int | None:
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index
    return None


def meta_lints(
    original: str, masked: str, start: int, end: int
) -> list[tuple[str, list[str], bool, int]]:
    calls: list[tuple[str, list[str], bool, int]] = []
    body = masked[start:end]
    for match in re.finditer(r"\b(allow|warn|expect)\s*\(", body):
        kind = match.group(1)
        open_paren = start + body.find("(", match.start())
        close_paren = matching(masked, open_paren, "(", ")")
        if close_paren is None or close_paren > end:
            continue

        lint_body_masked = masked[open_paren + 1 : close_paren]
        lint_body_original = original[open_paren + 1 : close_paren]
        lints: list[str] = []
        has_reason = False
        offset = 0
        for masked_item in lint_body_masked.split(","):
            item_len = len(masked_item)
            original_item = lint_body_original[offset : offset + item_len]
            offset += item_len + 1

            if re.match(r"^\s*reason\s*=", masked_item):
                has_reason = bool(re.search(r"\breason\s*=", original_item))
                continue
            path = re.match(
                r"^\s*([A-Za-z_][A-Za-z0-9_-]*(?:::[A-Za-z_][A-Za-z0-9_-]*)*)\s*$",
                masked_item,
            )
            if path is not None:
                lints.append(normalize_lint(path.group(1)))

        calls.append((kind, lints, has_reason, start + match.start()))
    return calls


def lint_attributes(text: str) -> list[tuple[str, list[str], bool, int]]:
    masked = mask_noncode(text)
    found: list[tuple[str, list[str], bool, int]] = []
    for match in re.finditer(r"#\s*!?\s*\[", masked):
        open_bracket = masked.find("[", match.start(), match.end())
        close_bracket = matching(masked, open_bracket, "[", "]")
        if close_bracket is None:
            continue

        body = masked[open_bracket + 1 : close_bracket]
        head = re.match(r"\s*([A-Za-z_][A-Za-z0-9_-]*)\b", body)
        if head is None or head.group(1) not in {"allow", "warn", "expect", "cfg_attr"}:
            continue

        found.extend(meta_lints(text, masked, open_bracket + 1, close_bracket))
    return found
