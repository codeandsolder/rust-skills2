#!/usr/bin/env python3
"""Reject broad or high-risk lint suppressions in handwritten Rust source.

The compiler is the primary policy mechanism. This checker makes selected lints
unsuppressible in handwritten source without using command-line `forbid`,
because proc macros legitimately inject internal lint allowances. It reads the *current nightly* group membership
from `clippy-driver -W help`, so the policy follows Clippy as lints move between
categories.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


BLOCKED_CLIPPY_GROUPS = {
    "clippy::correctness",
    "clippy::suspicious",
    "clippy::perf",
}
BLOCKED_EXPECT_LINTS = {
    "clippy::allow_attributes",
    "clippy::allow_attributes_without_reason",
    "clippy::await_holding_lock",
    "clippy::dbg_macro",
    "clippy::expect_used",
    "clippy::missing_safety_doc",
    "clippy::panic",
    "clippy::todo",
    "clippy::undocumented_unsafe_blocks",
    "clippy::unimplemented",
    "clippy::unwrap_used",
    "unexpected_cfgs",
    "unfulfilled_lint_expectations",
    "unsafe_op_in_unsafe_fn",
}
IGNORED_DIRS = {
    ".git",
    ".venv",
    "node_modules",
    "target",
    "vendor",
}


def normalize_lint(name: str) -> str:
    return name.strip().replace("-", "_")


def run_text(argv: list[str]) -> str:
    result = subprocess.run(
        argv,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if result.returncode != 0:
        print(f"rust-skills2: command failed: {' '.join(argv)}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        raise SystemExit(2)
    return result.stdout


def check_compiler_flag_policy() -> list[str]:
    """Reject rustflags that can cap or force lint levels below the gate."""
    violations: list[str] = []

    for name, value in sorted(os.environ.items()):
        is_rustflags = (
            name in {"RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_BUILD_RUSTFLAGS"}
            or (name.startswith("CARGO_TARGET_") and name.endswith("_RUSTFLAGS"))
        )
        if not is_rustflags:
            continue
        if "--cap-lints" in value or "--force-warn" in value:
            violations.append(
                f"environment {name} contains a lint-level override "
                f"(--cap-lints/--force-warn)"
            )

    config = run_text(["cargo", "+nightly", "-Z", "unstable-options", "config", "get"])
    for line in config.splitlines():
        if ".rustflags =" not in line and not line.startswith("build.rustflags ="):
            continue
        if "--cap-lints" in line or "--force-warn" in line:
            key = line.split("=", 1)[0].strip()
            violations.append(
                f"Cargo config {key} contains a lint-level override "
                f"(--cap-lints/--force-warn)"
            )

    return violations


def clippy_groups() -> tuple[set[str], dict[str, set[str]]]:
    output = run_text(["clippy-driver", "+nightly", "-W", "help"])
    groups: dict[str, set[str]] = {}

    in_groups = False
    for line in output.splitlines():
        if line.startswith("Lint groups provided by rustc:"):
            in_groups = True
            continue
        if line.startswith("Lint groups loaded by this crate:"):
            in_groups = True
            continue
        if line.startswith("Lint ") and line.endswith(":"):
            in_groups = False
            continue
        if not in_groups:
            continue

        match = re.match(r"^\s+([a-zA-Z0-9_:-]+)\s{2,}(.+)$", line)
        if match is None:
            continue

        group = normalize_lint(match.group(1))
        members = {
            normalize_lint(member)
            for member in match.group(2).split(",")
            if member.strip()
        }
        groups[group] = members

    missing = sorted(BLOCKED_CLIPPY_GROUPS - groups.keys())
    if missing:
        print(
            "rust-skills2: could not discover required Clippy groups: "
            + ", ".join(missing),
            file=sys.stderr,
        )
        raise SystemExit(2)

    return set(groups), groups


def workspace_packages() -> list[dict[str, object]]:
    metadata = json.loads(
        run_text(["cargo", "+nightly", "metadata", "--no-deps", "--format-version", "1"])
    )
    members = set(metadata["workspace_members"])
    return sorted(
        (package for package in metadata["packages"] if package["id"] in members),
        key=lambda package: package["manifest_path"],
    )


def generated_lint_boundaries(packages: list[dict[str, object]]) -> set[Path]:
    boundaries: set[Path] = set()
    violations: list[str] = []

    for package in packages:
        root = Path(str(package["manifest_path"])).resolve().parent
        package_metadata = package.get("metadata") or {}
        if not isinstance(package_metadata, dict):
            continue
        rust_skills2 = package_metadata.get("rust-skills2") or {}
        if not isinstance(rust_skills2, dict):
            violations.append(
                f"{root / 'Cargo.toml'}: package.metadata.rust-skills2 must be a table"
            )
            continue

        declared = rust_skills2.get("generated-lint-boundaries", [])
        if not isinstance(declared, list) or any(not isinstance(item, str) for item in declared):
            violations.append(
                f"{root / 'Cargo.toml'}: "
                "package.metadata.rust-skills2.generated-lint-boundaries must be an array of paths"
            )
            continue

        for relative in declared:
            relative_path = Path(relative)
            if relative_path.is_absolute():
                violations.append(
                    f"{root / 'Cargo.toml'}: generated lint boundary must be relative: {relative}"
                )
                continue

            candidate = (root / relative_path).resolve()
            try:
                candidate.relative_to(root)
            except ValueError:
                violations.append(
                    f"{root / 'Cargo.toml'}: generated lint boundary escapes package root: {relative}"
                )
                continue

            if candidate.suffix != ".rs":
                violations.append(
                    f"{root / 'Cargo.toml'}: generated lint boundary must name one .rs file: {relative}"
                )
                continue
            if not candidate.is_file():
                violations.append(
                    f"{root / 'Cargo.toml'}: generated lint boundary does not exist: {relative}"
                )
                continue
            boundaries.add(candidate)

    if violations:
        print("rust-skills2: invalid generated lint boundary metadata:", file=sys.stderr)
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        raise SystemExit(1)

    return boundaries


def rust_files(roots: list[Path]) -> list[Path]:
    found: set[Path] = set()
    for root in roots:
        for path in root.rglob("*.rs"):
            relative_parts = path.relative_to(root).parts[:-1]
            if any(part in IGNORED_DIRS for part in relative_parts):
                continue
            found.add(path.resolve())
    return sorted(found)


def mask_noncode(text: str) -> str:
    """Mask comments and string literals while preserving length/newlines."""
    chars = list(text)
    masked = list(text)
    length = len(text)
    i = 0

    def blank(start: int, end: int) -> None:
        for index in range(start, end):
            if masked[index] != "\n":
                masked[index] = " "

    while i < length:
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

        raw = re.match(r"(?:b|c)?r(#+)?\"", text[i:])
        if raw is not None:
            start = i
            hashes = raw.group(1) or ""
            i += raw.end()
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

        i += 1

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

def main() -> int:
    violations = check_compiler_flag_policy()
    group_names, groups = clippy_groups()
    blocked_members = set().union(*(groups[group] for group in BLOCKED_CLIPPY_GROUPS))

    expectation_count = 0
    packages = workspace_packages()
    roots = [Path(str(package["manifest_path"])).resolve().parent for package in packages]
    boundaries = generated_lint_boundaries(packages)
    files = rust_files(roots)

    for path in files:
        if path in boundaries:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            violations.append(f"{path}: non-UTF-8 Rust source cannot be policy-checked")
            continue

        for kind, lints, has_reason, offset in lint_attributes(text):
            line = text.count("\n", 0, offset) + 1
            location = f"{path}:{line}"

            if kind in {"allow", "warn"}:
                violations.append(
                    f"{location}: #[{kind}(...)] is forbidden in handwritten source; "
                    "it can lower the strict command-line lint level"
                )
                continue

            expectation_count += 1
            if len(lints) != 1:
                violations.append(
                    f"{location}: #[expect] must name exactly one lint; found {len(lints)}"
                )
            if not has_reason:
                violations.append(
                    f'{location}: #[expect] must include reason = "..."'
                )

            for lint in lints:
                if lint in group_names:
                    violations.append(
                        f"{location}: expectation of lint group {lint} is forbidden; "
                        "expect one specific suppressible lint instead"
                    )
                elif lint in blocked_members:
                    owner = next(
                        group
                        for group in BLOCKED_CLIPPY_GROUPS
                        if lint in groups[group]
                    )
                    violations.append(
                        f"{location}: {lint} belongs to {owner} on this nightly; "
                        "correctness/suspicious/perf expectations are forbidden"
                    )
                elif lint in BLOCKED_EXPECT_LINTS:
                    violations.append(
                        f"{location}: expectation of {lint} would weaken suppression policy"
                    )

    if violations:
        print("rust-skills2: source lint suppression policy violations:", file=sys.stderr)
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 1

    print(
        f"rust-skills2: source lint suppression policy OK "
        f"({len(files)} Rust files, {len(boundaries)} generated lint boundaries, "
        f"{expectation_count} expectation attributes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
