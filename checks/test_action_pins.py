import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_FILES = [
    ROOT / ".github/workflows/strict-rust.yml",
    ROOT / ".github/actions/rust-strict/action.yml",
    ROOT / ".github/actions/python-strict/action.yml",
    ROOT / ".github/actions/source-lint-policy/action.yml",
]
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def indented_block_contains(text: str, header: str, expected_line: str) -> bool:
    lines = text.splitlines()
    header_indent = len(header) - len(header.lstrip())
    for index, line in enumerate(lines):
        if line != header:
            continue
        for candidate in lines[index + 1 :]:
            if not candidate.strip():
                continue
            indent = len(candidate) - len(candidate.lstrip())
            if indent <= header_indent:
                break
            if candidate == expected_line:
                return True
    return False


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
selector = "runs-on: ${{ github.event.repository.private && fromJSON('[\"self-hosted\",\"Linux\",\"X64\",\"local-ci\"]') || 'ubuntu-24.04' }}"
if selector not in workflow:
    raise SystemExit("strict Rust visibility routing must use hosted Ubuntu for public and local Linux x64 for private")

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

provider_revisions: set[str] = set()
for action in ("setup-sccache", "finalize-sccache"):
    matcher = re.compile(
        rf"(?m)^\s*uses:\s*codeandsolder/ci-workflows/\.github/actions/"
        rf"{action}@([0-9a-f]{{40}})\s*# main\s*$"
    )
    matches = matcher.findall(workflow)
    if len(matches) != 1:
        raise SystemExit(
            f"strict reusable workflow must use exactly one immutable, "
            f"Renovate-tracked canonical {action} action; found {len(matches)}"
        )
    provider_revisions.add(matches[0])
if len(provider_revisions) != 1:
    raise SystemExit(
        "strict reusable workflow setup/finalize actions must pin the same "
        "provider commit SHA"
    )
for forbidden in (
    "Swatinem/rust-cache",
    "preserve-rustc-wrapper",
    "rustc-wrapper:",
    "sccache-server-port",
):
    if forbidden in workflow:
        raise SystemExit(f"strict reusable workflow retains obsolete cache escape hatch: {forbidden}")

quarantine_match = re.search(
    r"(?m)^        uses: codeandsolder/ci-workflows/\.github/actions/"
    r"cargo-release-quarantine@([0-9a-f]{40}) # main$",
    workflow,
)
if quarantine_match is None:
    raise SystemExit("strict Rust must pin the shared Cargo quarantine action")
if "if: github.event_name == 'pull_request'" not in workflow:
    raise SystemExit("Cargo quarantine must run on PRs only")
if "base-ref: ${{ github.event.pull_request.base.sha }}" not in workflow:
    raise SystemExit("Cargo quarantine must compare to the PR base")
if "lockfile: auto" not in workflow:
    raise SystemExit("Cargo quarantine must scan all tracked workspaces")
if quarantine_match.group(1) != next(iter(provider_revisions)):
    raise SystemExit("Cargo quarantine and sccache must use one trusted CI provider SHA")

python_action = (ROOT / ".github/actions/python-strict/action.yml").read_text()
if not indented_block_contains(
    python_action,
    "  ban-python-outside-ci:",
    '    default: "true"',
):
    raise SystemExit("strict Python composite must reject non-CI Python by default")
if not indented_block_contains(
    workflow,
    "      ban-python-outside-ci:",
    "        default: true",
):
    raise SystemExit("strict reusable workflow must reject non-CI Python by default")

print(
    "rust-skills2: strict gate refs are immutable, self-checkout is pinned to "
    "job.workflow_sha, and non-CI Python is denied by default"
)
