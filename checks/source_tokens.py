"""Independent Python reference for Rust source token and lint-attribute scanning."""

from __future__ import annotations

import re


def normalize_lint(name: str) -> str:
    return name.strip().replace("-", "_")


# Search only for complete token openings; ordinary Rust code needs no masking.
# Named alternatives preserve the original precedence without re-matching the
# same Unicode offset to classify an opening.
TOKEN_OPEN = re.compile(
    r"(?P<line>//)|(?P<block>/\*)|"
    r"(?P<character>(?:b)?'(?:[^'\\\n\r\t]|\\(?:[nrt\\0'\"]|x[0-9A-Fa-f]{2}|u\{[0-9A-Fa-f_]+\}))')|"
    r'(?P<raw>(?:b|c)?r(?P<hashes>#+)?")|(?P<string>b"|c"|")'
)
BLOCK_MARK = re.compile(r"/\*|\*/")
STRING_MARK = re.compile(r'\\[\s\S]?|"')


def mask_noncode(text: str) -> str:
    """Mask comments and string literals while preserving length/newlines."""
    pieces = []
    length = len(text)
    cursor = 0
    while cursor < length:
        opening = TOKEN_OPEN.search(text, cursor)
        if opening is None:
            break
        start = opening.start()
        end = opening.end()
        pieces.append(text[cursor:start])
        if opening.group("line") is not None:
            newline = text.find("\n", end)
            end = length if newline == -1 else newline
        elif opening.group("block") is not None:
            depth = 1
            while depth:
                mark = BLOCK_MARK.search(text, end)
                if mark is None:
                    end = length
                    break
                depth += 1 if mark.group() == "/*" else -1
                end = mark.end()
        elif opening.group("raw") is not None:
            terminator = '"' + (opening.group("hashes") or "")
            close = text.find(terminator, end)
            end = length if close == -1 else close + len(terminator)
        elif opening.group("string") is not None:
            while True:
                mark = STRING_MARK.search(text, end)
                if mark is None:
                    end = length
                    break
                end = mark.end()
                if mark.group() == '"':
                    break
        # Complete character literals already end at opening.end(). Lifetimes
        # and labels are not token openings, so remain unmodified.
        pieces.append("\n".join(" " * len(line) for line in text[start:end].split("\n")))
        cursor = end
    pieces.append(text[cursor:])
    return "".join(pieces)


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
