#!/usr/bin/env python3
"""Generate an experimental routed single-file corpus for automatic review.

This is deliberately parallel to REVIEW_SKILL.md so reviewer experiments can compare:

1. the compact all-rules corpus; and
2. a routed corpus with a small always-applied review core plus an explicit
   semantic activation condition for every ordinary rust-skills2 rule.

The canonical rule text remains rules/*.md. Routing predicates currently live in
checks/review_routing_conditions.json as experimental metadata. If the routed
shape wins empirically, they should move into the rule sources rather than
remaining a second authoring surface.

Usage:
    uv run --no-project python checks/gen_routed_review_skill.py
    uv run --no-project python checks/gen_routed_review_skill.py --check
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

from gen_index import CATEGORIES
from gen_review_skill import RULES, clean_body, ordered_rule_ids, prefix_of, source_bytes, summary_of

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ROUTING = HERE / "review_routing_conditions.json"
OUT = ROOT / "REVIEW_SKILL_ROUTED.md"

# These are review operations worth considering on every non-trivial change.
# They are intentionally about *how to review a change*, not Rust syntax or a
# subsystem that may be absent from the diff.
ALWAYS_RULES: tuple[tuple[str, str, str], ...] = (
    (
        "review-no-duplicate-logic",
        "Do not introduce a second implementation of behavior that already has one owner.",
        "Search the changed path and its siblings for equivalent logic before accepting new machinery. "
        "Flag duplication when the copies encode the same contract or invariant and can drift; repeated "
        "syntax that is independent by design is not itself a defect.",
    ),
    (
        "review-invariant-owner",
        "Put checks and fixes at the boundary that owns the invariant, not at a downstream symptom.",
        "Trace where the relevant state becomes valid or invalid. Prefer repairing that transition or "
        "construction boundary over filtering corrupted state later. A local check is still correct when "
        "that location genuinely owns the boundary.",
    ),
    (
        "review-behavior-preservation",
        "Compare observable behavior before and after the change, including unhappy paths.",
        "Review success results, errors, retries, fallback, shutdown, partial progress, and state transitions. "
        "Any observable change should be intentional and supported by the stated contract or tests rather "
        "than appearing as collateral damage.",
    ),
    (
        "review-complete-abstraction",
        "A new abstraction should own all equivalent paths it claims to replace.",
        "When a helper, type, or shared mechanism is introduced, inspect sibling call sites for the same "
        "bookkeeping or control flow. Partial migration is a defect when equivalent paths can now diverge; "
        "do not demand migration of merely similar but semantically separate code.",
    ),
    (
        "review-scope-discipline",
        "Keep a behavior change focused enough that its effects can be reviewed independently.",
        "Flag unrelated refactors, style churn, test rewrites, or API movement when they obscure the causal "
        "change or alter behavior without justification. Nearby cleanup that is required by the fix is in scope.",
    ),
    (
        "review-simplest-complete-design",
        "Prefer the smallest design that completely expresses the current requirement.",
        "After a redesign, look for obsolete branches, wrappers, compatibility shims, optional state, and "
        "single-use abstractions that no longer serve a real contract. Do not remove structure that carries "
        "a demonstrated API, platform, safety, or performance requirement.",
    ),
    (
        "review-contract-vs-implementation",
        "Make code, tests, comments, and stated change intent agree on the same contract.",
        "Use the implementation as evidence, not the prose as proof. Flag contradictions in claimed behavior, "
        "supported inputs, compatibility, or failure semantics, but do not invent requirements absent from the "
        "repository or change context.",
    ),
    (
        "review-regression-evidence",
        "Changed behavior should have evidence at the boundary where users or callers observe it.",
        "Prefer focused regression tests or other deterministic evidence that distinguish the broken and fixed "
        "behavior. An internal proxy is insufficient when fallback or another layer can make the end result pass "
        "without exercising the mechanism under review.",
    ),
    (
        "review-doc-attachment",
        "Verify that documentation and attributes still attach to the intended item after structural edits.",
        "Declaration movement can silently retarget a rustdoc comment or attribute without breaking compilation. "
        "Whenever structure changes near declarations, inspect the final source association; if no such structure "
        "moves, this check is effectively free.",
    ),
    (
        "review-implied-boundaries",
        "Exercise boundary cases implied by the changed contract rather than only the nominal example.",
        "Consider empty or missing values, malformed input, limits and overflow, partial I/O, platform/feature "
        "variants, cancellation, shutdown, and concurrency only where the changed behavior makes those boundaries "
        "plausible. Do not manufacture irrelevant edge cases.",
    ),
)

# General review rules learned from recurring real maintainer failures but only
# useful when a specific review surface is present. Unlike the Rust rule routing
# metadata, these are deliberately authored here as part of the experimental
# review representation rather than pretending they already exist in rules/*.md.
CONDITIONAL_REVIEW_RULES: tuple[tuple[str, str, str, str], ...] = (
    (
        "review-displayed-error",
        "The change adds or modifies error wrapping, context, diagnostics, logging, or error rendering call sites.",
        "Audit the error representation callers actually display or log, not only the stored source chain.",
        "Trace the final formatting boundary. Preserving an underlying source is insufficient when callers render "
        "only an outer Display string that drops the useful cause. Conversely, do not duplicate the source text "
        "when the real reporter already renders the chain.",
    ),
    (
        "review-state-regression",
        "The change modifies persistent, cached, queued, registered, or otherwise stateful bookkeeping and its transitions.",
        "Stateful fixes need evidence for both the immediate result and the resulting state.",
        "Check that success and failure leave the owner in a coherent state: no stale entries, leaked registrations, "
        "orphaned work, or poisoned cached values. A test that observes only the returned result can miss the invariant "
        "that actually regressed.",
    ),
    (
        "review-internal-compatibility",
        "The change adds optional state, wrapper APIs, duplicate constructors, or compatibility branches around crate-internal or test-only interfaces.",
        "Do not spend design complexity preserving interfaces that have no real external consumer.",
        "Identify actual downstream/public consumers before paying for compatibility. Crate-private and test-only call "
        "sites can usually be migrated directly; retain a shim only when a concrete compatibility contract requires it.",
    ),
    (
        "review-real-consumer-boundary",
        "The change exists to satisfy an external compiler, linker, protocol, service, file format, or other consumer contract.",
        "Validate behavior at the real consumer boundary rather than an internal proxy.",
        "Trace what the external consumer actually reads or observes and make the regression exercise that contract. "
        "An internal helper, environment probe, or intermediate buffer is not evidence when the consumer uses a different "
        "channel or representation.",
    ),
    (
        "review-fallback-masking",
        "The changed mechanism can retry, fall back, substitute another implementation, or otherwise succeed after the intended path fails.",
        "A green end result is insufficient when fallback can mask failure of the path under review.",
        "Assert evidence that the intended mechanism itself ran successfully, in addition to the final result. This is "
        "especially important for caches, remote/local execution, protocol negotiation, and best-effort accelerations.",
    ),
    (
        "review-implicit-inputs",
        "The change classifies behavior from visible arguments while response files, environment, metadata, or downstream discovery may also affect that behavior.",
        "Treat opaque and implicit inputs conservatively when deciding whether behavior is present.",
        "Do not infer a complete semantic property solely from argv or another partial view if supported inputs can encode "
        "the same fact elsewhere. Cover the implicit forms that the real consumer recognizes before suppressing or changing behavior.",
    ),
    (
        "review-concurrent-initialization",
        "The change adds or modifies lazy initialization, capability probing, memoization, or caches reachable by simultaneous first callers.",
        "First-call initialization must be atomic at the primitive that owns the cached value.",
        "Look for get-then-await-then-initialize races that duplicate probes or publish inconsistent state. Test simultaneous "
        "first callers rather than only warm-cache behavior, and use the primitive's atomic initializer when available.",
    ),
    (
        "review-concurrency-dedup-result",
        "The change deduplicates, coalesces, or coordinates concurrent operations that still need an externally useful result per caller.",
        "Concurrency deduplication must preserve both the coordination property and each caller's useful result.",
        "Tests should establish the intended amount of shared work and independently verify the returned state/result for "
        "every concurrent operation. Proving only that one probe ran does not prove all waiters observed correct behavior.",
    ),
    (
        "review-output-layout-owner",
        "The change adds human-readable rows, fields, columns, or spacing to output whose surrounding formatter already computes shared layout.",
        "Let the component that owns a formatted block also own new rows and layout decisions.",
        "Pass new data into the existing formatter when it already computes widths, indentation, or alignment. Parallel "
        "ad-hoc padding tends to drift as neighboring labels or terminal constraints change.",
    ),
    (
        "review-dependency-contract",
        "The change copies dependency cfg logic, target matrices, implementation details, or version-specific behavior into project-owned code.",
        "Depend on a dependency's public contract and encode only the project's own verified constraint.",
        "Private cfg expressions and implementation matrices can change independently of the public API. Determine which "
        "targets or versions the project itself must support, then express that narrower requirement directly.",
    ),
    (
        "review-external-baseline",
        "A regression test depends on external-tool behavior that varies by toolchain, platform, version, or environment.",
        "Establish the direct external-tool baseline before interpreting the mediated path.",
        "A self-calibrating test may skip where the tool lacks the capability, but a local skip is not positive validation. "
        "Exercise the full mediated path in at least one known-positive environment before claiming the regression is covered.",
    ),
    (
        "review-analogous-semantics",
        "The change adds or modifies one member of a family of sibling options, environment variables, config fields, or equivalent control-flow paths.",
        "Compare neighboring semantics before defining behavior for a new sibling mechanism.",
        "Check empty/missing values, precedence, fallback, errors, and defaults against the analogous existing paths. Divergence "
        "is fine when intentional, but accidental one-off semantics are hard for callers and maintainers to predict.",
    ),
    (
        "review-coupled-protocol-parts",
        "The changed external contract spans multiple coupled channels or resources such as environment state plus inherited descriptors or paired protocol fields.",
        "Preserve the whole coupled protocol contract rather than one visible component in isolation.",
        "Identify every part the consumer relies on and keep their identity/lifetime relationship intact. Copying a variable, "
        "token, or handle while dropping its paired resource can make the visible state look correct while the protocol is broken.",
    ),
)

FORBIDDEN_WHEN_PHRASES = (
    "when this rule applies",
    "when relevant",
    "if this rule applies",
    "if relevant",
)
RECOMMENDATION_PREFIXES = (
    "use ",
    "prefer ",
    "avoid ",
    "do not ",
    "don't ",
    "ensure ",
    "must ",
    "should ",
    "never ",
)


def source_summary_digest() -> str:
    digest = hashlib.sha256()
    for rule_id in sorted(path.stem for path in RULES.glob("*.md")):
        path = RULES / f"{rule_id}.md"
        summary = summary_of(path.read_text(encoding="utf-8").splitlines(), path)
        digest.update(rule_id.encode())
        digest.update(b"\0")
        digest.update(summary.encode())
        digest.update(b"\n")
    return digest.hexdigest()


def load_conditions() -> dict[str, str]:
    try:
        payload = json.loads(ROUTING.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing routing metadata: {ROUTING}") from exc
    expected_digest = source_summary_digest()
    actual_digest = payload.get("source_summary_sha256")
    if actual_digest != expected_digest:
        raise SystemExit(
            f"{ROUTING.name}: source summaries changed; routing predicates need review "
            f"(expected digest {expected_digest}, found {actual_digest!r})"
        )

    rows = payload.get("rules")
    if not isinstance(rows, list):
        raise SystemExit(f"{ROUTING.name}: expected top-level rules list")

    conditions: dict[str, str] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise SystemExit(f"{ROUTING.name}: every routing row must be an object")
        rule_id = row.get("id")
        when = row.get("when")
        if not isinstance(rule_id, str) or not isinstance(when, str):
            raise SystemExit(f"{ROUTING.name}: every row needs string id/when fields")
        when = " ".join(when.split()).strip()
        if rule_id in conditions:
            raise SystemExit(f"{ROUTING.name}: duplicate condition for {rule_id}")
        words = len(when.split())
        if words < 5 or words > 35:
            raise SystemExit(
                f"{ROUTING.name}: condition length out of range for {rule_id}: {words} words"
            )
        lowered = when.lower()
        if any(phrase in lowered for phrase in FORBIDDEN_WHEN_PHRASES):
            raise SystemExit(f"{ROUTING.name}: tautological condition for {rule_id}: {when!r}")
        if lowered.startswith(RECOMMENDATION_PREFIXES):
            raise SystemExit(
                f"{ROUTING.name}: condition is phrased as a recommendation for {rule_id}: {when!r}"
            )
        conditions[rule_id] = when

    expected = {path.stem for path in RULES.glob("*.md")}
    actual = set(conditions)
    if actual != expected:
        raise SystemExit(
            f"routing coverage mismatch: missing={sorted(expected - actual)}, "
            f"extra={sorted(actual - expected)}"
        )
    return conditions


def render() -> str:
    ordered = ordered_rule_ids()
    conditions = load_conditions()
    by_prefix: dict[str, list[str]] = {}
    for rule_id in ordered:
        by_prefix.setdefault(prefix_of(rule_id), []).append(rule_id)

    known_prefixes = {prefix for prefix, _title, _impact in CATEGORIES}
    stray = sorted(set(by_prefix) - known_prefixes)
    if stray:
        raise SystemExit(f"rules with unknown category prefix: {stray}")

    parts = [
        "# rust-skills2 — routed single-file review corpus",
        "",
        f"Experimental review representation: {len(ALWAYS_RULES)} always-applied review rules plus "
        f"{len(CONDITIONAL_REVIEW_RULES)} conditional general-review rules and {len(ordered)} conditional "
        f"Rust rules across {len(CATEGORIES)} categories. Generated from "
        "`rules/*.md` plus experimental routing predicates; edit the source rules, not this file.",
        "",
        "## Review protocol",
        "",
        "1. Read the whole change once for behavior, ownership, dataflow, and stated intent.",
        f"2. Apply all {len(ALWAYS_RULES)} rules in **Always apply** to every substantive review.",
        "3. Scan the **Conditional rule directory** and build an active set from every `WHEN` condition "
        "satisfied or plausibly implicated by the changed code or its contract.",
        "4. A matching `WHEN` means *inspect this rule*, not *report a defect*. If applicability is genuinely "
        "uncertain, include the rule in the active set; do not invent missing project requirements.",
        "5. Reason about findings using the always-applied rules plus the active conditional rules. Do not "
        "emit findings merely to demonstrate that a rule was considered.",
        "6. For each finding, identify the rule ID, exact trigger/location, consequence, and smallest robust "
        "fix. Distinguish proven defects from hypotheses needing measurement or additional context.",
        "",
        "The directory intentionally repeats each condition before the detailed cards. This makes the file "
        "usable both as one long prompt and as a two-stage corpus where a router first selects rule IDs and a "
        "second prompt receives only the always-applied cards plus those selected bodies.",
        "",
        "## Always apply",
        "",
    ]

    for rule_id, summary, body in ALWAYS_RULES:
        parts.extend([f"### `{rule_id}` — {summary}", "", body, ""])

    parts.extend(["## Conditional rule directory", "", "### General review conditions", ""])
    for rule_id, when, _summary, _body in CONDITIONAL_REVIEW_RULES:
        parts.append(f"- `{rule_id}` — **WHEN:** {when}")
    parts.append("")

    for number, (prefix, title, impact) in enumerate(CATEGORIES, 1):
        parts.extend([f"### {number}. {title} ({impact})", ""])
        for rule_id in by_prefix.get(prefix, []):
            parts.append(f"- `{rule_id}` — **WHEN:** {conditions[rule_id]}")
        parts.append("")

    parts.extend(["## Conditional rule bodies", "", "### General review conditions", ""])
    for rule_id, when, summary, body in CONDITIONAL_REVIEW_RULES:
        parts.extend([f"#### `{rule_id}` — {summary}", "", f"**WHEN:** {when}", "", body, ""])

    seen: set[str] = set()
    for number, (prefix, title, impact) in enumerate(CATEGORIES, 1):
        parts.extend([f"### {number}. {title} ({impact})", ""])
        for rule_id in by_prefix.get(prefix, []):
            path = RULES / f"{rule_id}.md"
            lines = path.read_text(encoding="utf-8").splitlines()
            summary = summary_of(lines, path)
            body = clean_body(lines, rule_id)
            if rule_id in seen:
                raise SystemExit(f"duplicate generated rule: {rule_id}")
            seen.add(rule_id)
            parts.extend(
                [
                    f"#### `{rule_id}` — {summary}",
                    "",
                    f"**WHEN:** {conditions[rule_id]}",
                    "",
                ]
            )
            if body:
                parts.extend([body, ""])

    expected = {path.stem for path in RULES.glob("*.md")}
    if seen != expected:
        raise SystemExit(
            f"coverage mismatch: missing={sorted(expected - seen)}, extra={sorted(seen - expected)}"
        )

    text = "\n".join(parts).rstrip() + "\n"
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = re.sub(r"\[([^\]]+)\]\(\./[a-z0-9-]+\.md\)", r"\1", text)
    if "```" in text or "~~~" in text:
        raise SystemExit("generated routed corpus unexpectedly contains a code fence")
    return text


def main() -> None:
    generated = render()
    size = len(generated.encode())
    source = source_bytes()
    ratio = 100 * size / source if source else 0.0
    ordinary_count = len(ordered_rule_ids())

    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != generated:
            print(
                "OUT OF DATE: REVIEW_SKILL_ROUTED.md — run "
                "`uv run --no-project python checks/gen_routed_review_skill.py`"
            )
            raise SystemExit(1)
        print(
            f"OK: REVIEW_SKILL_ROUTED.md current ({len(ALWAYS_RULES)} always + "
            f"{len(CONDITIONAL_REVIEW_RULES)} review-conditional + {ordinary_count} Rust-conditional rules, "
            f"{size} bytes, {ratio:.1f}% of source corpus)"
        )
        return

    OUT.write_text(generated, encoding="utf-8")
    print(
        f"wrote {OUT.name}: {len(ALWAYS_RULES)} always + {len(CONDITIONAL_REVIEW_RULES)} "
        f"review-conditional + {ordinary_count} Rust-conditional rules, {size} bytes "
        f"({ratio:.1f}% of source corpus)"
    )


if __name__ == "__main__":
    main()
