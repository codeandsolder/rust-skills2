#!/usr/bin/env python3
"""Reject Rust GitHub Actions jobs that bypass the canonical sccache setup."""

from __future__ import annotations

import argparse
import re
import shlex
from pathlib import Path
from typing import Any

import yaml

CANONICAL_WORKFLOW = "codeandsolder/ci-workflows/.github/workflows/rust-sccache.yml@"
STRICT_WORKFLOW = "codeandsolder/rust-skills2/.github/workflows/strict-rust.yml@"
CANONICAL_SETUP = "codeandsolder/ci-workflows/.github/actions/setup-sccache@"
CANONICAL_FINALIZE = "codeandsolder/ci-workflows/.github/actions/finalize-sccache@"
LOCAL_SETUP_SUFFIX = "/.github/actions/setup-sccache"
LOCAL_FINALIZE_SUFFIX = "/.github/actions/finalize-sccache"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
CARGO_NON_COMPILING = {
    "add",
    "audit",
    "clean",
    "deny",
    "fetch",
    "fmt",
    "generate-lockfile",
    "info",
    "init",
    "locate-project",
    "login",
    "logout",
    "machete",
    "metadata",
    "new",
    "owner",
    "pkgid",
    "read-manifest",
    "remove",
    "report",
    "search",
    "tree",
    "update",
    "vendor",
    "verify-project",
    "yank",
}
PROBE_ARGS = {"--help", "-h", "--version", "-V", "-vV"}
RUST_COMPILE_ACTIONS = (
    "houseabsolute/actions-rust-cross@",
)



def external_ref(uses: str, prefix: str) -> str | None:
    if not uses.startswith(prefix):
        return None
    return uses[len(prefix) :].split(" #", 1)[0].strip()


def is_full_sha_use(uses: str, prefix: str) -> bool:
    ref = external_ref(uses, prefix)
    return ref is not None and FULL_SHA.fullmatch(ref) is not None


def cargo_tokens_compile(tokens: list[str]) -> bool:
    while tokens and tokens[0].startswith("+"):
        tokens.pop(0)
    if not tokens:
        return False
    if tokens[0] in PROBE_ARGS:
        return False
    subcommand = tokens[0]
    if subcommand in CARGO_NON_COMPILING:
        return False
    if subcommand in {"package", "publish"} and "--no-verify" in tokens[1:]:
        return False
    # Unknown cargo subcommands are cache-required by default. Cargo plugins can
    # invoke rustc internally, and silently exempting a new compiling subcommand
    # would break the invariant.
    return True


SHELL_BOUNDARY = {";", "&&", "||", "|", "&"}
CONTROL_PREFIX = {"if", "then", "do", "while", "until", "!", "command"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def shell_segment_compiles(tokens: list[str]) -> bool:
    while tokens and (tokens[0] in CONTROL_PREFIX or ASSIGNMENT_RE.match(tokens[0])):
        tokens.pop(0)
    if not tokens:
        return False

    if tokens[0] == "env":
        tokens.pop(0)
        while tokens:
            token = tokens[0]
            if token in {"-u", "--unset"} and len(tokens) >= 2:
                del tokens[:2]
                continue
            if token.startswith("-") or ASSIGNMENT_RE.match(token):
                tokens.pop(0)
                continue
            break
    if not tokens:
        return False

    if tokens[:2] == ["rustup", "run"] and len(tokens) >= 4:
        tokens = tokens[3:]
    if not tokens:
        return False

    command = tokens[0]
    args = tokens[1:]
    if command == "cargo":
        return cargo_tokens_compile(args)
    if command in {"rustc", "rustdoc", "clippy-driver"}:
        return bool(args) and args[0] not in PROBE_ARGS
    return False


def shell_line_compiles(line: str) -> bool:
    try:
        lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = "#"
        tokens = list(lexer)
    except ValueError:
        # Fall back only for unmistakable compiler command spellings when shell
        # quoting is malformed.
        return bool(re.search(r"(?:^|[;&|]\s*)(?:cargo|rustc|rustdoc|clippy-driver)(?:\s|\+)", line))

    segment: list[str] = []
    for token in [*tokens, ";"]:
        if token in SHELL_BOUNDARY or (token and set(token) <= {";", "&", "|"}):
            if shell_segment_compiles(segment):
                return True
            segment = []
        else:
            segment.append(token)
    return False


def run_mentions_rust(run: str) -> bool:
    heredoc_terminator: str | None = None
    for raw_line in run.splitlines():
        stripped = raw_line.strip()
        if heredoc_terminator is not None:
            if stripped == heredoc_terminator:
                heredoc_terminator = None
            continue
        if not stripped or stripped.startswith("#"):
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", stripped)
        if heredoc is not None:
            heredoc_terminator = heredoc.group(1)
        # Strip the ordinary unquoted shell-comment form. Quoted '#' is unusual
        # in compiler command lines; keeping this simple avoids pretending to be
        # a full shell parser.
        line = re.sub(r"\s+#.*$", "", stripped)
        if shell_line_compiles(line):
            return True
    return False


def step_mentions_rust(step: Any) -> bool:
    if not isinstance(step, dict):
        return False
    run = step.get("run")
    if isinstance(run, str) and run_mentions_rust(run):
        return True
    uses = step.get("uses")
    if not isinstance(uses, str):
        return False
    lowered = uses.lower()
    if uses.startswith("./"):
        # Local Rust policy/actions are Rust work even if the actual Cargo call
        # is nested in the composite action.
        return any(token in lowered for token in ("rust-strict", "cargo-build", "cargo-test", "clippy"))
    if lowered.startswith("actions-rs/cargo@"):
        with_args = step.get("with")
        command = str(with_args.get("command", "")) if isinstance(with_args, dict) else ""
        args = str(with_args.get("args", "")) if isinstance(with_args, dict) else ""
        try:
            tokens = [command, *shlex.split(args)] if command else []
        except ValueError:
            return True
        return cargo_tokens_compile(tokens)
    return any(lowered.startswith(prefix) for prefix in RUST_COMPILE_ACTIONS)


def canonical_step_kind(uses: str) -> str | None:
    if is_full_sha_use(uses, CANONICAL_SETUP) or uses.endswith(LOCAL_SETUP_SUFFIX):
        return "setup"
    if is_full_sha_use(uses, CANONICAL_FINALIZE) or uses.endswith(LOCAL_FINALIZE_SUFFIX):
        return "finalize"
    return None


def inspect_job(path: Path, job_name: str, job: Any, strict_ref: str | None) -> list[str]:
    if not isinstance(job, dict):
        return []
    violations: list[str] = []
    job_uses = job.get("uses")
    if isinstance(job_uses, str):
        if job_uses.startswith(CANONICAL_WORKFLOW):
            if not is_full_sha_use(job_uses, CANONICAL_WORKFLOW):
                violations.append(f"{path}:{job_name}: shared Rust CI ref must be a full commit SHA")
            return violations
        if job_uses.startswith(STRICT_WORKFLOW):
            ref = external_ref(job_uses, STRICT_WORKFLOW)
            if ref is None or not FULL_SHA.fullmatch(ref):
                violations.append(f"{path}:{job_name}: strict Rust workflow ref must be a full commit SHA")
            elif strict_ref is not None and ref != strict_ref:
                violations.append(
                    f"{path}:{job_name}: strict Rust workflow uses {ref[:12]}, "
                    f"but the executing gate is {strict_ref[:12]}"
                )
            return violations
        return violations

    steps = job.get("steps")
    if not isinstance(steps, list):
        return violations

    rust_indices = [index for index, step in enumerate(steps) if step_mentions_rust(step)]
    setup_indices: list[int] = []
    finalize_indices: list[int] = []
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            continue
        uses = step.get("uses")
        if not isinstance(uses, str):
            continue
        kind = canonical_step_kind(uses)
        if kind == "setup":
            setup_indices.append(index)
        elif kind == "finalize":
            finalize_indices.append(index)
        if uses.lower().startswith("swatinem/rust-cache@"):
            violations.append(f"{path}:{job_name}: Swatinem/rust-cache is forbidden; use canonical sccache")

    if not rust_indices:
        return violations

    first_rust = min(rust_indices)
    last_rust = max(rust_indices)
    if not setup_indices:
        violations.append(f"{path}:{job_name}: Rust job is missing canonical setup-sccache")
    elif min(setup_indices) > first_rust:
        violations.append(f"{path}:{job_name}: setup-sccache runs after Rust tooling")

    if not finalize_indices:
        violations.append(f"{path}:{job_name}: Rust job is missing canonical finalize-sccache")
    elif max(finalize_indices) < last_rust:
        violations.append(f"{path}:{job_name}: finalize-sccache runs before the last Rust tooling step")
    else:
        for index in finalize_indices:
            step = steps[index]
            if isinstance(step, dict) and str(step.get("if", "")).strip() != "always()":
                violations.append(f"{path}:{job_name}: finalize-sccache must use if: always()")

    return violations


def inspect_root(root: Path, strict_ref: str | None = None) -> list[str]:
    workflows = root / ".github" / "workflows"
    if not workflows.is_dir():
        return []
    violations: list[str] = []
    for path in sorted((*workflows.glob("*.yml"), *workflows.glob("*.yaml"))):
        try:
            data = yaml.safe_load(path.read_text())
        except yaml.YAMLError as exc:
            violations.append(f"{path}: invalid YAML: {exc}")
            continue
        if not isinstance(data, dict):
            continue
        jobs = data.get("jobs")
        if not isinstance(jobs, dict):
            continue
        for name, job in jobs.items():
            violations.extend(inspect_job(path.relative_to(root), str(name), job, strict_ref))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--strict-ref", help="Expected rust-skills2 strict workflow SHA")
    args = parser.parse_args()
    root = args.root.resolve()
    violations = inspect_root(root, args.strict_ref)
    if violations:
        print("rust-skills2: Rust CI sccache policy violations:")
        for violation in violations:
            print(f"- {violation}")
        return 1
    print("rust-skills2: every detected Rust CI job uses canonical sccache")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
