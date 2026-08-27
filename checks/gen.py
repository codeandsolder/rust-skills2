#!/usr/bin/env python3
"""Extract Rust code blocks from ../rules/*.md into Cargo examples.

Recommended and anti-pattern examples are strict by default: blocks under a
heading beginning with "Good" or "Bad" get expectation `compile`. Other legacy
snippets retain the older heuristics unless they opt in to explicit metadata.

An example can override its expectation with an HTML comment immediately above
the fence:

    <!-- rust-check: compile -->
    <!-- rust-check: fragment; reason=uses domain types defined elsewhere -->
    <!-- rust-check: compile_fail; reason=demonstrates a type error -->
    <!-- rust-check: ignore; reason=requires a proc-macro crate -->
    <!-- rust-check: nightly(portable_simd); reason=nightly-only API -->

Native rustdoc fence attributes are also honored for compile semantics:

    ```rust,compile_fail
    ```rust,ignore
    ```rust,no_run          # still expected to compile
    ```rust,should_panic    # still expected to compile

An explicit rust-check marker may add a more specific expectation/reason, but it
must not contradict a native compile_fail/ignore fence attribute.

Expectations are written to manifest.json for analyze.py.
"""
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
RULES = (HERE.parent / "rules").resolve()
OUT = HERE / "examples"
OUT.mkdir(exist_ok=True)
for f in OUT.glob("*.rs"):
    f.unlink()

placeholder = re.compile(r"\b(my_crate|mycrate|mylib|my_app|my_project|my_lib|mycrate_derive)\b")
placeholder_use = re.compile(r"\buse\s+(model|transport|service|internal|app|domain)\b")
MARKER = re.compile(
    r"^<!--\s*rust-check:\s*"
    r"(compile|fragment|compile_fail|ignore|nightly(?:\([^)]*\))?)"
    r"(?:\s*;\s*reason=(.*?))?\s*-->$"
)
FENCE = re.compile(r"^```rust(?P<attrs>\s*(?:,[^`]*)?)\s*$")

HEADER = (
    "#![allow(unused, dead_code, unreachable_code, unused_imports, "
    "unused_variables, unused_mut, unused_assignments, unused_macros, "
    "non_local_definitions)]\n"
)


def explicit_marker(lines, fence_index):
    i = fence_index - 1
    while i >= 0 and not lines[i].strip():
        i -= 1
    if i < 0:
        return None
    m = MARKER.match(lines[i].strip())
    if not m:
        return None
    raw, reason = m.groups()
    if raw.startswith("nightly"):
        feature = raw[len("nightly"):].strip("()") or None
        expect = "nightly"
        if not reason and feature:
            reason = f"requires nightly feature {feature}"
    else:
        expect = raw
    if expect in {"fragment", "compile_fail", "ignore"} and not reason:
        raise SystemExit(
            f"explicit rust-check {expect!r} before line {fence_index + 1} "
            "requires `; reason=...`"
        )
    return expect, reason or "explicit expectation"


def native_fence_expectation(fence_match, *, file, line):
    """Map rustdoc fence flags that change compile expectations.

    `no_run` and `should_panic` still need to type-check, so they intentionally
    do not override the section/default expectation. Target-specific rustdoc
    ignore flags are also left alone rather than pretending an all-target skip
    has the same semantics.
    """
    raw = (fence_match.group("attrs") or "").strip()
    if not raw:
        return None
    if raw.startswith(","):
        raw = raw[1:]
    attrs = {part.strip() for part in raw.split(",") if part.strip()}

    compile_fail = "compile_fail" in attrs
    ignore = "ignore" in attrs
    if compile_fail and ignore:
        raise SystemExit(
            f"conflicting rustdoc fence attributes compile_fail+ignore in "
            f"{file}:{line}"
        )
    if compile_fail:
        return "compile_fail", "native rustdoc `compile_fail` fence"
    if ignore:
        return "ignore", "native rustdoc `ignore` fence"
    return None


def resolve_expectation(lines, fence_index, fence_match, block, section, md_name):
    marker = explicit_marker(lines, fence_index)
    native = native_fence_expectation(
        fence_match, file=md_name, line=fence_index + 1
    )
    if marker and native and marker[0] != native[0]:
        raise SystemExit(
            f"conflicting rust-check {marker[0]!r} and rustdoc fence "
            f"{native[0]!r} in {md_name}:{fence_index + 1}"
        )
    return marker or native or legacy_expectation(block, section)


def legacy_expectation(block, section):
    """Keep legacy classification outside strict Good/Bad sections."""
    if section.strip().lower().startswith("good"):
        return "compile", "Good sections compile by default"
    if section.strip().lower().startswith("bad"):
        return "compile", "Bad sections compile by default"
    if "#![feature" in block:
        return "nightly", "legacy nightly feature gate"
    if "proc_macro" in block:
        return "ignore", "legacy proc-macro snippet requires a proc-macro crate"
    if placeholder.search(block) or placeholder_use.search(block):
        return "ignore", "legacy placeholder/domain crate names"
    if any(ln.strip() == "..." for ln in block.splitlines()):
        return "ignore", "legacy bare pseudocode ellipsis"
    return "auto", "legacy classifier"


def wrap(block):
    has_main = re.search(r"\bfn\s+main\s*\(", block) is not None
    has_inner_attr = "#![" in block
    has_mod = re.search(r"(?m)^\s*(pub(\([^)]*\))?\s+)?mod\s+\w", block) is not None
    if has_main:
        return HEADER + block + "\n"
    if has_inner_attr or has_mod:
        return HEADER + block + "\nfn main() {}\n"
    return (
        HEADER
        + "async fn __ex() -> Result<(), Box<dyn std::error::Error>> {\n"
        + block
        + "\n;\nOk(())\n}\nfn main() {}\n"
    )


manifest = {}
scanned = generated = 0
for md in sorted(RULES.glob("*.md")):
    lines = md.read_text(encoding="utf-8").splitlines()
    section = ""
    file_index = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^#{2,}\s+(.*)", line)
        if m:
            section = m.group(1).strip()
        fence_match = FENCE.match(line.strip())
        if fence_match:
            start = i + 1
            j = start
            while j < len(lines) and lines[j].strip() != "```":
                j += 1
            block = "\n".join(lines[start:j])
            expect, reason = resolve_expectation(
                lines, i, fence_match, block, section, md.name
            )
            name = f"{md.stem.replace('-', '_')}__{file_index}"
            info = {
                "file": md.name,
                "line": start + 1,
                "section": section,
                "expect": expect,
                "reason": reason,
                "generated": expect not in {"ignore", "nightly"},
            }
            manifest[name] = info
            if info["generated"]:
                (OUT / f"{name}.rs").write_text(wrap(block), encoding="utf-8")
                generated += 1
            scanned += 1
            file_index += 1
            i = j
        i += 1

(HERE / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(f"generated {generated} example files (scanned {scanned} rust blocks)")
counts = {}
for info in manifest.values():
    counts[info["expect"]] = counts.get(info["expect"], 0) + 1
print("expectations: " + ", ".join(f"{k}={counts[k]}" for k in sorted(counts)))
