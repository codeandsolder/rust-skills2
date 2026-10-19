#!/usr/bin/env python3
"""Generate the compact single-file corpus used for long-context Rust review.

The source of truth remains rules/*.md. REVIEW_SKILL.md keeps every rule ID and
summary plus review-relevant rationale, decision criteria, caveats, and exact
API/lint terminology, while dropping the expensive teaching scaffolding:
fenced examples, example commentary, cross-link lists, bibliographies, and
explicitly unrelated tangents.

Usage:
    uv run --no-project python checks/gen_review_skill.py
    uv run --no-project python checks/gen_review_skill.py --check
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from gen_index import CATEGORIES

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
RULES = ROOT / "rules"
SKILL = ROOT / "SKILL.md"
OUT = ROOT / "REVIEW_SKILL.md"

DROP_SECTIONS = {"see also", "references", "sources"}
DROP_SECTION_MARKERS = ("unrelated",)
EXAMPLE_SECTION_PREFIXES = ("good", "bad")
FULL_SECTION_MARKERS = (
    "decision",
    "practical",
    "review questions",
    "key points",
    "caveat",
    "when to",
    "checklist",
    "guidance",
    "pitfall",
    "choosing",
    "which to",
    "tradeoff",
    "requirement",
    "rules of thumb",
    "enforcement",
    "limitation",
)
NORMATIVE = re.compile(
    r"\b(?:avoid|choose|consider|do not|don't|ensure|if|keep|measure|must|never|"
    r"only|prefer|reject|require|should|unless|use|when)\b",
    re.IGNORECASE,
)
RUST_CHECK_COMMENT = re.compile(r"^\s*<!--\s*rust-check:")
RULE_LINE = re.compile(r"^\*\*Rule\*\*:\s*`[^`]+`\s*$", re.IGNORECASE)
HEADING = re.compile(r"^(#{2,6})\s+(.+?)\s*$")
RULE_LINK = re.compile(r"rules/([a-z0-9-]+)\.md")
SUMMARY = re.compile(r"^>\s+(.+?)\s*$")


def prefix_of(rule_id: str) -> str:
    return rule_id.split("-", 1)[0] + "-"


def ordered_rule_ids() -> list[str]:
    """Preserve the curated category/rule order already exposed by SKILL.md."""
    available = {path.stem for path in RULES.glob("*.md")}
    ordered: list[str] = []
    seen: set[str] = set()
    for match in RULE_LINK.finditer(SKILL.read_text(encoding="utf-8")):
        rule_id = match.group(1)
        if rule_id in available and rule_id not in seen:
            ordered.append(rule_id)
            seen.add(rule_id)
    ordered.extend(sorted(available - seen))
    return ordered


def summary_of(lines: list[str], path: Path) -> str:
    for line in lines:
        match = SUMMARY.match(line)
        if match:
            return match.group(1)
    raise SystemExit(f"{path.name}: missing '> summary' line")


def strip_fenced_code(lines: list[str]) -> list[str]:
    """Drop fenced code and rust-check metadata while retaining prose around it."""
    out: list[str] = []
    in_fence = False
    fence = ""
    for line in lines:
        stripped = line.lstrip()
        if not in_fence and (stripped.startswith("```") or stripped.startswith("~~~")):
            in_fence = True
            fence = stripped[:3]
            continue
        if in_fence:
            if stripped.startswith(fence):
                in_fence = False
                fence = ""
            continue
        if RUST_CHECK_COMMENT.match(line):
            continue
        out.append(line.rstrip())
    if in_fence:
        raise SystemExit("unterminated Markdown code fence")
    return out


def section_blocks(lines: list[str]) -> list[tuple[str | None, list[str]]]:
    """Split on h2+ headings so each section can be compacted independently."""
    blocks: list[tuple[str | None, list[str]]] = []
    heading: str | None = None
    body: list[str] = []
    for line in lines:
        match = HEADING.match(line)
        if match:
            blocks.append((heading, body))
            heading = match.group(2).strip()
            body = []
        else:
            body.append(line)
    blocks.append((heading, body))
    return blocks


def paragraph_blocks(lines: list[str]) -> list[list[str]]:
    blocks: list[list[str]] = []
    current: list[str] = []
    for line in [*lines, ""]:
        if line.strip():
            current.append(line.rstrip())
        elif current:
            blocks.append(current)
            current = []
    return blocks


def is_list_or_table(block: list[str]) -> bool:
    first = block[0].lstrip()
    return first.startswith(("- ", "* ", "|", "1. ", "2. ", "3. ", "4. ", "5. "))


def compact_inline(block: list[str]) -> str:
    """Flatten one prose block for dense rule-card rendering."""
    return " ".join(line.strip() for line in block).strip()


def clean_body(lines: list[str], rule_id: str) -> str:
    lines = strip_fenced_code(lines)

    while lines and not lines[0].strip():
        lines.pop(0)
    if lines and lines[0].strip() == f"# {rule_id}":
        lines.pop(0)

    filtered: list[str] = []
    removed_summary = False
    for line in lines:
        if not removed_summary and SUMMARY.match(line):
            removed_summary = True
            continue
        if RULE_LINE.match(line.strip()):
            continue
        filtered.append(line)

    rendered: list[str] = []
    for heading, body in section_blocks(filtered):
        label = (heading or "").strip()
        lowered = label.lower()
        if lowered in DROP_SECTIONS or any(
            marker in lowered for marker in DROP_SECTION_MARKERS
        ):
            continue

        # Good/Bad sections chiefly annotate removed examples. A descriptive
        # heading still encodes a useful recommendation, so retain just that.
        if any(
            lowered.startswith(prefix) for prefix in EXAMPLE_SECTION_PREFIXES
        ):
            if ":" in label:
                kind, description = label.split(":", 1)
                verb = (
                    "Prefer"
                    if kind.strip().lower().startswith("good")
                    else "Avoid"
                )
                rendered.append(f"- {verb}: {description.strip()}")
            continue

        paragraphs = paragraph_blocks(body)
        if not paragraphs:
            continue

        if lowered == "why it matters":
            # Two paragraphs is enough to retain the motivating model and its
            # principal qualification without copying the tutorial that follows.
            for paragraph in paragraphs[:2]:
                rendered.append(compact_inline(paragraph))
            continue

        if any(marker in lowered for marker in FULL_SECTION_MARKERS):
            # Explicit decision/caveat/checklist sections are already distilled
            # review material. Keep them, but flatten prose for token efficiency.
            rendered.append(f"**{label}:**")
            for paragraph in paragraphs:
                if is_list_or_table(paragraph):
                    rendered.extend(paragraph)
                else:
                    rendered.append(compact_inline(paragraph))
            continue

        # All other subsections are examples, API/release-note elaboration, or
        # secondary detail. If the heading itself states a review instruction,
        # keep that instruction; otherwise the rule summary + rationale carry the
        # durable rule without paying to reproduce tutorial prose.
        if NORMATIVE.search(label):
            rendered.append(f"- {label}")

    return "\n".join(rendered).strip()


def render() -> str:
    ordered = ordered_rule_ids()
    by_prefix: dict[str, list[str]] = {}
    for rule_id in ordered:
        by_prefix.setdefault(prefix_of(rule_id), []).append(rule_id)

    known_prefixes = {prefix for prefix, _title, _impact in CATEGORIES}
    stray = sorted(set(by_prefix) - known_prefixes)
    if stray:
        raise SystemExit(f"rules with unknown category prefix: {stray}")

    parts = [
        "# rust-skills2 — single-file review corpus",
        "",
        f"{len(ordered)} Rust rules across {len(CATEGORIES)} categories, optimized for "
        "long-context automatic code review. Generated from `rules/*.md`; edit the "
        "source rules, not this file.",
        "",
        "## Review contract",
        "",
        "Apply only rules whose preconditions are present in the code under review. "
        "Treat category priority as review order, not as permission to ignore lower-"
        "priority correctness issues. Prefer concrete defects over stylistic churn, "
        "and do not invent compatibility, MSRV, performance, or API requirements.",
        "",
        "Trace behavior and ownership before style. Check boundary and malformed "
        "inputs, overflow, partial I/O, cancellation, shutdown, concurrency, and "
        "unsafe invariants when relevant. A rule's conditions and exceptions are "
        "part of the rule; do not mechanically apply its headline.",
        "",
        "For each finding, identify the rule ID, exact location/trigger, consequence, "
        "and smallest robust fix. Do not emit a finding merely to demonstrate that a "
        "rule was considered. Distinguish proven defects from hypotheses that need "
        "measurement or additional context.",
        "",
        "This corpus removes fenced teaching examples, example commentary, `See Also` "
        "lists, bibliographies, and tangents explicitly marked as unrelated. It retains "
        "every rule ID and summary plus compact rationale, decision criteria, caveats, "
        "and normative guidance.",
        "",
    ]

    index_rows = [
        "| # | Category | Impact | Prefix | Rules |",
        "|---:|---|---|---|---:|",
    ]
    for number, (prefix, title, impact) in enumerate(CATEGORIES, 1):
        index_rows.append(
            f"| {number} | {title} | {impact} | `{prefix}` | "
            f"{len(by_prefix.get(prefix, []))} |"
        )
    parts.extend(["## Category order", "", *index_rows, ""])

    seen: set[str] = set()
    for number, (prefix, title, impact) in enumerate(CATEGORIES, 1):
        parts.extend([f"## {number}. {title} ({impact})", ""])
        for rule_id in by_prefix.get(prefix, []):
            path = RULES / f"{rule_id}.md"
            lines = path.read_text(encoding="utf-8").splitlines()
            summary = summary_of(lines, path)
            body = clean_body(lines, rule_id)
            if rule_id in seen:
                raise SystemExit(f"duplicate generated rule: {rule_id}")
            seen.add(rule_id)
            parts.extend([f"### `{rule_id}` — {summary}", ""])
            if body:
                parts.extend([body, ""])

    expected = {path.stem for path in RULES.glob("*.md")}
    if seen != expected:
        missing = sorted(expected - seen)
        extra = sorted(seen - expected)
        raise SystemExit(f"coverage mismatch: missing={missing}, extra={extra}")

    text = "\n".join(parts).rstrip() + "\n"
    text = re.sub(r"\n{3,}", "\n\n", text)
    # A pasted single-file corpus should not depend on the per-rule file layout.
    # Preserve useful link labels while removing internal relative Markdown links.
    text = re.sub(r"\[([^\]]+)\]\(\./[a-z0-9-]+\.md\)", r"\1", text)
    if "```" in text or "~~~" in text:
        raise SystemExit("generated corpus unexpectedly contains a code fence")
    return text


def source_bytes() -> int:
    return sum(path.stat().st_size for path in RULES.glob("*.md"))


def main() -> None:
    generated = render()
    size = len(generated.encode())
    source = source_bytes()
    ratio = 100 * size / source if source else 0.0

    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != generated:
            print(
                "OUT OF DATE: REVIEW_SKILL.md — run "
                "`uv run --no-project python checks/gen_review_skill.py`"
            )
            raise SystemExit(1)
        print(
            f"OK: REVIEW_SKILL.md current ({len(ordered_rule_ids())} rules, "
            f"{size} bytes, {ratio:.1f}% of source corpus)"
        )
        return

    OUT.write_text(generated, encoding="utf-8")
    print(
        f"wrote {OUT.name}: {len(ordered_rule_ids())} rules, {size} bytes "
        f"({ratio:.1f}% of source corpus)"
    )


if __name__ == "__main__":
    main()
