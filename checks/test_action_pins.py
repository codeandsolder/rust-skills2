#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
GATE_FILES = [
    ROOT / ".github/workflows/strict-rust.yml",
    ROOT / ".github/actions/rust-strict/action.yml",
    ROOT / ".github/actions/python-strict/action.yml",
    ROOT / ".github/actions/source-lint-policy/action.yml",
]
SHA_RE = re.compile(r"^[0-9a-f]{40}$")

for path in GATE_FILES:
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        match = re.search(r"\buses:\s*([^\s#]+)", line)
        if match is None:
            continue
        ref = match.group(1)
        if ref.startswith("./"):
            continue
        if "@" not in ref:
            raise SystemExit(f"{path}:{lineno}: external action lacks an immutable ref: {ref}")
        _, revision = ref.rsplit("@", 1)
        if not SHA_RE.fullmatch(revision):
            raise SystemExit(f"{path}:{lineno}: external action ref is not a full commit SHA: {ref}")

workflow = (ROOT / ".github/workflows/strict-rust.yml").read_text()
required = [
    "repository: ${{ job.workflow_repository }}",
    "ref: ${{ job.workflow_sha }}",
    "uses: ./.rust-skills2-gate/.github/actions/python-strict",
    "uses: ./.rust-skills2-gate/.github/actions/rust-strict",
    "sparse-checkout: |",
    "      .github/actions",
    "      scripts",
    "sparse-checkout-cone-mode: true",
]
for needle in required:
    if needle not in workflow:
        raise SystemExit(f"strict reusable workflow is missing immutable self-checkout contract: {needle}")
if "codeandsolder/rust-skills2/.github/actions/" in workflow:
    raise SystemExit("strict reusable workflow must not call rust-skills2 composite actions through a remote ref")

python_action = (ROOT / ".github/actions/python-strict/action.yml").read_text()
if re.search(
    r'(?ms)^  ban-python-outside-ci:\n(?:    .*\n)*?    default: "true"$',
    python_action,
) is None:
    raise SystemExit("strict Python composite must reject non-CI Python by default")
if re.search(
    r"(?ms)^      ban-python-outside-ci:\n(?:        .*\n)*?        default: true$",
    workflow,
) is None:
    raise SystemExit("strict reusable workflow must reject non-CI Python by default")

print(
    "rust-skills2: strict gate refs are immutable, self-checkout is pinned to "
    "job.workflow_sha, and non-CI Python is denied by default"
)
